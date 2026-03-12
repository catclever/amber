require_relative '../base_tool'

module Amber
  module Tool
    class UpdateContext < Base
      def self.tool_name
        'update_context'
      end

      def self.description
        "Save a key-value pair to the Persistent Context (Soul). Use this to pass extracted data or final results to downstream jobs."
      end

      def self.parameters
        {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "The name of the variable to store (e.g. 'total_sales' or 'report_path')."
            },
            value: {
              type: "string",
              description: "The string value or JSON string to store."
            }
          },
          required: ["key", "value"]
        }
      end

      def execute(args, context = nil)
        raise ArgumentError, "Context is required for update_context tool" unless context
        
        key = args['key'].to_sym
        value = args['value']
        
        context.set(key, value)
        
        "Successfully saved `#{key}` to the Persistent Context."
      rescue StandardError => e
        "Failed to update context: #{e.message}"
      end
    end
  end
end
