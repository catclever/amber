require 'ruby_llm'
require 'logger'
require_relative 'message_queue'
require_relative 'working_note'
require_relative 'token_monitor'
require_relative '../tool_registry'
require_relative 'message_queue'
require_relative 'working_note'
require_relative '../tool_registry'

module Amber
  module Agent
    class Base
      attr_reader :name, :system_prompt, :llm

      def initialize(name:, profile_name: 'openai', system_prompt: nil, tools: [], logger: nil, max_turns: 30)
        @name = name.to_sym
        @system_prompt = system_prompt || "You are a helpful AI assistant. You must use tools to submit your result."
        @max_turns = max_turns
        
        @logger = logger || Logger.new($stdout, level: Logger::INFO)
        
        @tools = tools.map do |t|
          if t.is_a?(Symbol) || t.is_a?(String)
            tool_class = Amber::ToolRegistry.get_tool(t)
            @logger.warn "[Amber::Agent::Base] Tool '#{t}' not found in registry." unless tool_class
            tool_class
          else
            t
          end
        end.compact
        
        # Merge explicitly requested tools with base survival tools from the Registry
        default_tools = Amber::ToolRegistry.get_default_tools
        default_tools.each do |dt|
          @tools << dt unless @tools.include?(dt)
        end
        
        # Initialize ruby_llm instance using profile name
        @llm = RubyLlm::LLMService.new(profile_name: profile_name, logger: @logger)
      end

      # The execution loop given a job context
      def execute(context, job_description, run_max_turns: nil)
        @logger.info "[Amber::Agent::#{@name}] Starting Agent Loop for job: #{job_description}"
        
        # 1. Prepare isolated Agent components
        # Initialize Message Queue with the agent's LLM for sliding window summarization
        queue = MessageQueue.new(@logger, llm: @llm)
        working_note = WorkingNote.new
        
        queue.seed_prompt(build_initial_prompt(context, job_description))

        # 2. ReAct / Tool Dispatch Loop
        turns = 0
        actual_max_turns = run_max_turns || @max_turns

        loop do
          turns += 1
          if turns > actual_max_turns
            @logger.warn "[Amber::Agent::#{@name}] Exceeded max turns (#{actual_max_turns}). Forcing exit."
            return "Error: Agent exceeded maximum allowed reasoning turns."
          end

          # Stage 1 Eviction Warning (Heartbeat Check)
          queue.heartbeat_check!
          
          # Stage 2 Eviction (Sliding Window)
          queue.evict!

          @logger.debug "[Amber::Agent::#{@name}] Turn #{turns} - Calling LLM..."
          
          # Inject WorkingNote state dynamically into the System Prompt for this turn
          dynamic_system_prompt = @system_prompt.dup
          unless working_note.empty?
            dynamic_system_prompt << "\n\n<WORKING_NOTE_STATE>\n"
            dynamic_system_prompt << "The following are your private notes retrieved from memory. "
            dynamic_system_prompt << "Use `write_working_note` to update them if necessary.\n"
            working_note.dump.each do |k, v|
              dynamic_system_prompt << "[#{k}]: #{v}\n"
            end
            dynamic_system_prompt << "</WORKING_NOTE_STATE>\n"
          end
          
          # Call ruby_llm with full history and registered tools
          llm_tools = @tools.map(&:to_llm_schema)

          response = @llm.call_with_system(
            system_prompt: dynamic_system_prompt,
            conversation_history: queue.to_llm_payload,
            tools: llm_tools
          )

          # Add Assistant's response to history
          queue.add({ role: 'assistant', content: response.content || "", tool_calls: response.tool_calls })

          # If the LLM didn't call any tools, we warn it and force it to.
          unless response.has_tool_calls?
            @logger.warn "[Amber::Agent::#{@name}] Turn #{turns} - LLM responded without tools. Prompting to use tools."
            @logger.debug "\n--- DEBUG LLM RAW STRING ---\n#{response.content}\n--- END DEBUG ---"
            
            queue.add({ 
              role: 'user', 
              content: "You must use the provided tools to interact with the environment or submit your final answer via 'send_message'. Plain text replies are discarded." 
            })
            next
          end

          # 3. Execute requested tools
          @logger.info "[Amber::Agent::#{@name}] LLM requested #{response.tool_calls.size} tool(s)."
          
          # Return value tracking - if a yielding tool like 'send_message' is called, we break the loop
          job_finished = false
          final_result = nil

          response.tool_calls.each do |tool_call|
            tool_name = tool_call.dig(:function, :name)
            tool_args_json = tool_call.dig(:function, :arguments)
            tool_call_id = tool_call[:id] || "call_#{rand(1000)}" # Fallback for some formats
            
            @logger.debug "[Amber::Agent::#{@name}] Executing Tool: #{tool_name} with args: #{tool_args_json}"
            
            # Lookup the tool class to check if it yields control
            tool_class = @tools.find { |t| t.tool_name == tool_name }
            
            tool_result = execute_tool(tool_name, tool_args_json, context, working_note)
            
            # If the LLM used an Explicit Yield tool, flag loop for exit
            if tool_class && tool_class.yields_control?
              job_finished = true
              final_result = tool_result
            end

            # Append tool result back to history so LLM can observe it in the next loop
            queue.add({ 
              role: 'tool', 
              tool_call_id: tool_call_id, 
              name: tool_name, 
              content: tool_result.to_s 
            })
          end

          if job_finished
             @logger.info "[Amber::Agent::#{@name}] Finished execution via explicit submission."
             return final_result
          end
        end
      end

      private

      def build_initial_prompt(context, job_description)
        <<~PROMPT
          Your goal is to complete the following job:
          "#{job_description}"
          
          Here is your current shared context environment snapshot:
          #{context.snapshot.to_json}
          
          Explore the environment using your tools. Once finished, you MUST call 'send_message'.
        PROMPT
      end

      def execute_tool(tool_name, args_json, context, working_note)
        tool_class = @tools.find { |t| t.tool_name == tool_name }
        
        unless tool_class
          @logger.error "Agent tried to call unknown tool: #{tool_name}"
          return "Error: Unknown tool '#{tool_name}'"
        end

        begin
          args_hash = JSON.parse(args_json)
          tool_instance = tool_class.new(context, working_note)
          tool_instance.execute(args_hash)
        rescue StandardError => e
          @logger.error "Tool execution failed: #{e.message}"
          "Error executing tool: #{e.message}"
        end
      end
    end
  end
end
