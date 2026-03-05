require 'ruby_llm'
require 'logger'

module Amber
  module Agent
    class Base
      attr_reader :name, :system_prompt, :llm

      def initialize(name:, profile_name: 'openai', system_prompt: nil, tools: [], logger: nil)
        @name = name.to_sym
        @system_prompt = system_prompt || "You are a helpful AI assistant."
        @tools = tools
        @logger = logger || Logger.new($stdout, level: Logger::INFO)
        
        # Initialize ruby_llm instance using profile name
        @llm = RubyLlm::LLMService.new(profile_name: profile_name, logger: @logger)
      end

      # The execution loop given a job context
      def execute(context, job_description)
        @logger.info "[Amber::Agent::#{@name}] Starting Agent Loop for job: #{job_description}"
        
        # 1. Prepare initial conversation history
        history = [
          { role: 'user', content: build_initial_prompt(context, job_description) }
        ]

        # 2. ReAct / Tool Dispatch Loop
        max_turns = 10
        turns = 0

        loop do
          turns += 1
          if turns > max_turns
            @logger.warn "[Amber::Agent::#{@name}] Exceeded max turns (#{max_turns}). Forcing exit."
            return "Error: Agent exceeded maximum allowed reasoning turns."
          end

          @logger.debug "[Amber::Agent::#{@name}] Turn #{turns} - Calling LLM..."
          
          # Call ruby_llm with full history and registered tools
          response = @llm.call_with_system(
            system_prompt: @system_prompt,
            conversation_history: history,
            tools: @tools.empty? ? nil : @tools
          )

          # Add Assistant's response to history
          history << { role: 'assistant', content: response.content, tool_calls: response.tool_calls }

          # If the LLM didn't call any tools, we assume it has reached a final conclusion.
          unless response.has_tool_calls?
            @logger.info "[Amber::Agent::#{@name}] Finished execution. Final answer obtained."
            return response.content
          end

          # 3. Execute requested tools
          @logger.info "[Amber::Agent::#{@name}] LLM requested #{response.tool_calls.size} tool(s)."
          
          response.tool_calls.each do |tool_call|
            tool_name = tool_call.dig(:function, :name)
            tool_args_json = tool_call.dig(:function, :arguments)
            tool_call_id = tool_call[:id] || "call_#{rand(1000)}" # Fallback for some formats
            
            @logger.debug "[Amber::Agent::#{@name}] Executing Tool: #{tool_name} with args: #{tool_args_json}"
            
            tool_result = execute_tool(tool_name, tool_args_json, context)
            
            # Append tool result back to history so LLM can observe it in the next loop
            history << { 
              role: 'tool', 
              tool_call_id: tool_call_id, 
              name: tool_name, 
              content: tool_result.to_s 
            }
          end
        end
      end

      private

      def build_initial_prompt(context, job_description)
        <<~PROMPT
          Your goal is to complete the following job:
          "#{job_description}"
          
          Here is your current shared context environment:
          #{context.snapshot.inspect}
          
          Use your available tools to investigate, mutate the context, and ultimately answer the prompt or report success.
        PROMPT
      end

      def execute_tool(tool_name, args_json, context)
        # TODO: Lookup from ToolRegistry and Sandbox Executor.
        # For now, stub the execution logic.
        @logger.warn "Tool #{tool_name} is not registered yet. Returning a stub."
        "Tool executed successfully (Stubbed)"
      end
    end
  end
end
