module Amber
  module Agent
    class TokenMonitor
      # Inspired by letta/services/context_window_calculator/token_counter.py
      # Approx Token Counter using bytes / 4 heuristic
      APPROX_BYTES_PER_TOKEN = 4
      SAFETY_MARGIN = 1.3

      def count_message_tokens(messages)
        return 0 if messages.nil? || messages.empty?

        # Convert to JSON to approximate the raw text string size sent to LLM
        text = messages.to_json
        byte_len = text.bytesize
        
        # Calculate tokens with safety margin
        base_tokens = (byte_len + APPROX_BYTES_PER_TOKEN - 1) / APPROX_BYTES_PER_TOKEN
        (base_tokens * SAFETY_MARGIN).to_i
      end
    end
  end
end
