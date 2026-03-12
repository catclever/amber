module Amber
  module Agent
    class MessageQueue
      attr_reader :history

      attr_reader :history, :token_monitor

      def initialize(logger, max_tokens: 100_000, llm: nil)
        @logger = logger
        @max_tokens = max_tokens
        @llm = llm # Used for summarization during eviction
        @warning_threshold = (max_tokens * 0.7).to_i
        @eviction_threshold = (max_tokens * 0.9).to_i
        
        @history = []
        @token_monitor = TokenMonitor.new
      end

      # Adds the initial prompt block to history.
      # Must be called first.
      def seed_prompt(content)
        @history << { role: 'user', content: content }
      end

      # Add standard message
      def add(msg_hash)
        @history << msg_hash
      end

      # Core mechanism for Stage 2 Eviction (Token/Turn Sliding Window)
      def evict!
        current_tokens = @token_monitor.count_message_tokens(@history)
        return if current_tokens <= @eviction_threshold

        @logger.warn "[Amber::MessageQueue] Eviction Triggered: Token limit exceeded (#{current_tokens} > #{@eviction_threshold}). Compressing history."

        # 1. Separate existing summary if present
        existing_summary = nil
        working_messages = @history.dup

        if working_messages[0] && working_messages[0][:role] == 'system' && working_messages[0][:content].to_s.include?("summary of the previous messages")
          existing_summary = working_messages.shift # Remove existing summary from active rounds
        end
        seed_prompt = working_messages.shift # Remove the very first system prompt

        # 2. Group into interaction rounds
        rounds = group_into_rounds(working_messages)
        total_rounds = rounds.size
        
        # 3. Evict 50% of the rounds
        evict_round_count = [1, (total_rounds * 0.5).to_i].max
        evict_rounds = rounds.first(evict_round_count)
        keep_rounds = rounds.last(total_rounds - evict_round_count)

        evicted_messages = evict_rounds.flatten
        kept_messages = keep_rounds.flatten

        @logger.info "[Amber::MessageQueue] Evicting #{evict_round_count}/#{total_rounds} rounds (#{evicted_messages.size} messages)"

        # 4. Synthesize Summary using LLM
        if @llm
          new_summary_text = generate_summary(evicted_messages, existing_summary)
          summary_msg = {
            role: 'system',
            content: "Note: prior messages from the beginning of the conversation have been hidden from view due to memory constraints.\nThe following is a summary of the previous messages:\n #{new_summary_text}"
          }
          @history = [seed_prompt, summary_msg] + kept_messages
        else
          @logger.warn "[Amber::MessageQueue] No LLM provided for summarization. Hard clipping history."
          @history = [seed_prompt] + kept_messages
        end
        
        @logger.info "[Amber::MessageQueue] Eviction complete. New token size roughly: #{@token_monitor.count_message_tokens(@history)}"
      end

      # Core mechanism for Stage 1 Eviction Warning
      # Injects a warning if the history is getting long and a recent warning hasn't been emitted
      def heartbeat_check!
        current_tokens = @token_monitor.count_message_tokens(@history)
        return false if current_tokens <= @warning_threshold
        
        # Don't inject if we've already warned in the last 3 turns
        recent_warning = @history.last(3).any? do |msg| 
          msg[:content].to_s.include?("Memory limit approaching")
        end
        return false if recent_warning

        @logger.warn "[Amber::MessageQueue] Heartbeat Warning: Injecting memory limit warning (#{current_tokens} tokens)."
        @history << { 
          role: 'user', 
          content: "[WARNING] Memory limit approaching. Your context window is filling up. Please summarize important context into your 'inner_thought', or submit the final result using a yielding tool (e.g. 'send_message') if your job is completed." 
        }
        true
      end

      # Formats history array into RubyLLM expected format (array of hashes)
      def to_llm_payload
        @history
      end

      private

      def group_into_rounds(messages)
        rounds = []
        i = 0
        while i < messages.size
          msg = messages[i]
          role = msg[:role].to_s

          if role == 'assistant'
            # Group assistant + subsequent tool results together
            group = [msg]
            i += 1
            while i < messages.size && messages[i][:role].to_s == 'tool'
              group << messages[i]
              i += 1
            end
            rounds << group
          else
            rounds << [msg]
            i += 1
          end
        end
        rounds
      end

      def generate_summary(evicted_messages, existing_summary)
        transcript = evicted_messages.map { |m| m.to_json }.join("\n")
        
        prompt = <<~PROMPT
          The following messages are being evicted from the BEGINNING of your context window. Write a detailed summary that captures what happened in these messages to appear BEFORE the remaining recent messages in context, providing background for what comes after.
          
          Make sure to capture High-level goals, what happened, important details (files, functions, configs), errors and fixes, and lookup hints. Write in first person as a factual record. Be thorough and detailed. Keep summary under 300 words.
          
        PROMPT
        
        if existing_summary
          prompt += "## Existing History Summary (Build upon this)\n#{existing_summary[:content]}\n\n"
        end
        
        prompt += "## New Transcript to compress\n#{transcript}"
        
        # Request summary using the LLM directly, no tools
        response = @llm.call(prompt)
        response.content.to_s
      end

    end
  end
end
