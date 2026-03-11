require_relative 'context'
require_relative 'orchestration/job'
require_relative 'agent/base'
require_relative 'engine/planner'
require_relative 'engine/evaluator'
require 'logger'

module Amber
  class Engine
    include Planner
    include Evaluator

    attr_reader :context, :jobs

    def self.build(&block)
      engine = new
      engine.instance_eval(&block) if block_given?
      engine
    end

    def initialize
      @context = Context.new
      @jobs = {}
      @agents = {}
      @logger = Logger.new($stdout)
      @logger.level = Logger::INFO
      
      # We instantiate a lightweight zero-temperature LLM just for Engine condition evaluations
      # Defaulting to glm based on current user setup
      @engine_evaluator = RubyLlm::LLMService.new(
        profile_name: 'glm2', 
        temperature: 0.1, 
        logger: @logger
      )
    end

    # DSL: Initialize the starting state of context
    def environment(hash)
      @context.merge(hash)
    end

    # DSL: Define a reusable agent instance
    def agent(name, **kwargs)
      @agents[name.to_sym] = Agent::Base.new(name: name, logger: @logger, **kwargs)
    end



    # DSL: Define a job
    def job(name, &block)
      j = Orchestration::Job.new(name)
      
      # Expose agents to the block context for `executed_by_agent` DSL calls
      j.instance_variable_set(:@available_agents, @agents)
      
      def j.executed_by_agent(agent_name)
        agent_instance = @available_agents[agent_name.to_sym]
        raise ArgumentError, "Agent '#{agent_name}' not defined." unless agent_instance
        
        executed_by do |ctx|
          agent_instance.execute(ctx, @description)
        end
      end
      
      # evaluate the job DSL methods (action, depends_on, executed_by, etc.)
      j.instance_eval(&block) if block_given?
      @jobs[name.to_sym] = j
    end

    # Execution Entrypoint
    def run!
      @logger.info "[Amber] Starting Engine with #{@jobs.size} defined jobs."
      
      # Track active threads for concurrent job execution
      @active_threads = []
      
      loop do
        intercept_dynamic_jobs!

        pending_jobs = @jobs.values.select { |j| j.status == :pending }
        running_jobs = @jobs.values.select { |j| j.status == :running }

        # Clean up finished threads
        @active_threads.reject! { |t| !t.alive? }

        break if pending_jobs.empty? && running_jobs.empty? && @active_threads.empty?

        ready_jobs = pending_jobs.select do |j|
          dependencies_met?(j)
        end

        if ready_jobs.empty? && running_jobs.empty? && @active_threads.empty?
          @logger.error "[Amber] DEADLOCK: No jobs are running and no pending jobs have their dependencies met. Terminating."
          break
        end

        ready_jobs.each do |j|
          @logger.info "[Amber] Dispatching Job: :#{j.name} (Concurrent Thread)"
          j.instance_variable_set(:@status, :running) # Mark early so it's not picked up again
          
          # Spawn real concurrent thread
          t = Thread.new do
            begin
              j.execute!(@context)
              @logger.info "[Amber] Finished Job: :#{j.name} with status: #{j.status}"
            rescue StandardError => e
              @logger.error "[Amber] Job :#{j.name} crashed: #{e.message}\n#{e.backtrace.join("\n")}"
              j.instance_variable_set(:@status, :failed)
            ensure
              # Write status to context so subsequent jobs can depend on it via symbol
              statuses = @context.get(:__amber_job_status) || {}
              statuses[j.name] = j.status
              @context.set(:__amber_job_status, statuses)
            end
          end
          
          @active_threads << t
        end

        # Throttling to prevent busy-wait
        sleep(0.1) unless ready_jobs.any?
      end
      
      # Final wait to ensure all threads finish gracefully
      @active_threads.each(&:join)

      @logger.info "[Amber] Engine Run Complete. Final Context: #{@context.snapshot.inspect}"
    end

    private

    def intercept_dynamic_jobs!
      queue = @context.get(:__amber_dynamic_jobs)
      return if queue.nil? || queue.empty?

      queue.each do |job_spec|
        job_sym = job_spec[:name].to_sym
        next if @jobs.key?(job_sym) # Skip if already spawned

        @logger.info "[Amber] Intercepted new Dynamic Job Spawn: :#{job_sym}"
        j = Orchestration::Job.new(job_sym)
        j.instance_variable_set(:@description, job_spec[:objective])
        
        j.depends_on_ai(job_spec[:condition]) if job_spec[:condition] && !job_spec[:condition].empty?
        
        # If no explicit agent is defined, auto-execute with the first generic execution agent available
        valid_agents = @agents.reject { |k, _v| k == :__amber_planner }.values
        if valid_agents.any?
          agent_instance = valid_agents.first
          run_max_turns = job_spec[:max_turns] ? job_spec[:max_turns].to_i : nil
          
          j.executed_by do |ctx|
            agent_instance.execute(ctx, j.description, run_max_turns: run_max_turns)
          end
        end
        
        @jobs[job_sym] = j
      end
      
      @context.set(:__amber_dynamic_jobs, [])
    end


  end
end
