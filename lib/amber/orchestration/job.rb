module Amber
  module Orchestration
    class Job
      attr_reader :name, :description, :dependencies, :ai_dependencies, :status, :result
      attr_reader :execution_agent, :max_turns, :execution_block

      # status can be :pending, :running, :completed, :failed
      def initialize(name)
        @name = name.to_sym
        @description = "Job: #{@name}"
        @dependencies = [] # Array of procs evaluating context
        @ai_dependencies = []
        @status = :pending
        @result = nil
        
        @execution_agent = nil
        @execution_block = nil
        @max_turns = nil
      end

      # DSL: action description or Getter
      def description(desc = nil)
        return @description if desc.nil?
        @description = desc
      end

      # e.g. depends_on { |ctx| ctx.get(:user_id) != nil }
      # or depends_on :some_other_job
      def depends_on(*job_names, &block)
        if block_given?
          @dependencies << block
        end
        job_names.each do |job_name|
          @dependencies << ->(ctx) { ctx.get(:__amber_job_status, job_name) == :completed }
        end
      end

      # DSL: Semantic/AI dependency rules to evaluate against Context
      def depends_on_ai(requirement)
        @ai_dependencies << requirement
      end

      # DSL: Assign an AI Agent from the Body Roster
      def assignee(agent_sym)
        @execution_agent = agent_sym.to_sym
      end

      # DSL: Assign pure Ruby block
      def execute(&block)
        raise ArgumentError, "Cannot define both execute and assignee for a single Job." if @execution_agent
        @execution_block = block
      end
      
      def execute_ruby!(ctx)
        @status = :running
        begin
          if @execution_block
            @result = @execution_block.call(ctx)
          end
          @status = :completed
        rescue StandardError => e
          @result = e
          @status = :failed
          raise e
        end
        @result
      end
    end
  end
end
