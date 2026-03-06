require_relative 'base_tool'
require_relative '../sandbox/executor'

module Amber
  module Tool
    class CodeExecutor < Base
      name 'execute_ruby_code'
      description 'Execute dynamic Ruby code in a secure, isolated sandbox to perform complex calculations, data transformations, or interact with an isolated workspace namespace.'
      parameters(
        type: 'object',
        properties: {
          code: { type: 'string', description: 'The raw Ruby code to evaluate. Must not use system calls like `system` or backticks.' }
        },
        required: ['code']
      )

      def execute(args)
        code = args['code']
        executor = Amber::Sandbox::Executor.new(memory_limit_mb: 200, cpu_limit_sec: 10)
        
        begin
          result = executor.execute(code)
          "Execution successful. Result: #{result.inspect}"
        rescue Amber::Sandbox::Executor::TimeoutError => e
          "Execution failed due to Timeout (Infinite Loop detected): #{e.message}"
        rescue Amber::Sandbox::Executor::SecurityError => e
          "Execution blocked by Security Policy: #{e.message}"
        rescue Amber::Sandbox::Executor::ExecutionError => e
          "Execution encountered an error: #{e.message}"
        rescue StandardError => e
          "Unknown Error: #{e.message}"
        end
      end
    end
  end
end
