require 'tmpdir'
require 'timeout'

module Amber
  module Sandbox
    class Executor
      class Error < StandardError; end
      class TimeoutError < Error; end
      class SecurityError < Error; end
      class ExecutionError < Error; end

      def initialize(memory_limit_mb: 200, cpu_limit_sec: 5)
        @memory_limit_mb = memory_limit_mb
        @cpu_limit_sec = cpu_limit_sec
      end

      def execute(code)
        validate_ast!(code)

        Dir.mktmpdir("amber_workspace_") do |workspace_dir|
          run_in_subprocess(code, workspace_dir)
        end
      end

      private

      def validate_ast!(code)
        # Parse the code to ensure there are no explicitly blocked method calls
        ast = RubyVM::AbstractSyntaxTree.parse(code)
        check_node(ast)
      rescue SyntaxError => e
        raise ExecutionError, "Syntax error in provided code: #{e.message}"
      end

      FORBIDDEN_METHODS = %i[system exec spawn fork syscall ` setrlimit exit exit! abort].freeze

      def check_node(node)
        return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)

        if node.type == :FCALL || node.type == :VCALL || node.type == :CALL
          # For CALL nodes, the method name is typically the second object
          method_name = node.type == :CALL ? node.children[1] : node.children[0]
          
          if FORBIDDEN_METHODS.include?(method_name)
            raise SecurityError, "Forbidden method call detected: #{method_name}"
          end
        elsif node.type == :XSTR # Backticks `ls`
          raise SecurityError, "Backtick (system command) execution is forbidden."
        end

        node.children.each do |child|
          check_node(child)
        end
      end

      def run_in_subprocess(code, workspace_dir)
        reader, writer = IO.pipe

        pid = Process.fork do
          reader.close
          
          begin
            # Apply resource limits
            if Process.respond_to?(:setrlimit)
              # CPU limits in seconds
              Process.setrlimit(Process::RLIMIT_CPU, @cpu_limit_sec)
              
              # Memory limit in bytes (Address space)
              begin
                Process.setrlimit(Process::RLIMIT_AS, @memory_limit_mb * 1024 * 1024)
              rescue StandardError, NotImplementedError
                # skip if not supported or fails on OS
              end
            end
            
            # Wipe environment variables to prevent token leakage
            ENV.clear
            
            # Change to isolated tmp workspace
            Dir.chdir(workspace_dir)
            
            result = eval(code, binding, "amber_sandbox", 1)
            
            payload = Marshal.dump({ status: :success, result: result })
            writer.write(payload)
          rescue Exception => e
            payload = Marshal.dump({ status: :error, class: e.class.name, message: e.message, backtrace: e.backtrace })
            writer.write(payload)
          ensure
            writer.close
            exit!(0)
          end
        end

        writer.close
        
        begin
          Timeout.timeout(@cpu_limit_sec + 2) do
            Process.wait(pid)
          end
        rescue Timeout::Error
          Process.kill('KILL', pid)
          Process.wait(pid)
          raise TimeoutError, "Sandbox execution timed out after #{@cpu_limit_sec} seconds."
        end

        output = reader.read
        reader.close

        if $?.exited? && $?.exitstatus == 0
          return nil if output.empty?
          
          # Safely load the payload
          data = Marshal.load(output)
          if data[:status] == :success
            data[:result]
          else
            raise ExecutionError, "#{data[:class]}: #{data[:message]}\n" + Array(data[:backtrace]).join("\n")
          end
        else
          if $?.termsig == 24 || $?.termsig == 9
            raise TimeoutError, "Sandbox execution timed out (CPU limit exceeded)."
          else
            raise ExecutionError, "Subprocess crashed or was killed by signal: #{$?.termsig}"
          end
        end
      end
    end
  end
end
