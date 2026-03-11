module Amber
  module Orchestration
    class Job
      attr_reader :name, :description, :dependencies, :ai_dependencies, :status, :result

      # status can be :pending, :running, :completed, :failed
      def initialize(name)
        @name = name.to_sym
        @description = "Dynamic Job: #{@name}"
        @dependencies = [] # Array of procs evaluating context
        @ai_dependencies = []
        @status = :pending
        @result = nil
        @execution_block = nil
      end

      # DSL: action description 
      def action(desc)
        @description = desc
      end

      # DSL: Formal dependency (evaluates a block against the context)
      # e.g. depends_on { |ctx| ctx.get(:user_id) != nil }
      # or depends_on :some_other_job
      def depends_on(*job_names, &block)
        if block_given?
          @dependencies << block
        end
        job_names.each do |job_name|
          # We store a lambda that checks the Engine context for completion
          # but Engine needs to evaluate this against its @jobs list.
          @dependencies << ->(ctx) { ctx.get(:__amber_job_status, job_name) == :completed }
        end
      end

      # DSL: Semantic/AI dependency rules to evaluate against Context
      def depends_on_ai(requirement)
        @ai_dependencies << requirement
      end

      # DSL: The block that executes the logic (or dynamic generation if missing)
      def executed_by(&block)
        @execution_block = block
      end

      def execute!(context)
        @status = :running
        
        begin
          if @execution_block
            @result = @execution_block.call(context)
          else
            # Default fallback: dynamic agent execution based on description + context
            @result = execute_dynamic_agent(context)
          end
          
          @status = :completed
        rescue StandardError => e
          @result = e
          @status = :failed
        end
        
        @result
      end

      private

      def execute_dynamic_agent(context)
        # TODO: Tie into ruby_llm and Sandbox CodeExecutor as per Plan Stage 4.
        # For now, print a placeholder message.
        puts "[Amber::Job::#{@name}] Automatically executing undefined job: '#{@description}'"
        # Return a semantic payload as if an AI did the work
        true
      end
    end
  end
end
