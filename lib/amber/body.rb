require 'logger'
require_relative 'agent/base'
require_relative 'body/planner'
require_relative 'body/evaluator'

module Amber
  class Body
    include Body::Planner
    include Body::Evaluator

    attr_reader :agents, :profiles, :logger, :engine_evaluator

    def self.define(name = :default, &block)
      body = new(name)
      body.instance_eval(&block) if block_given?
      body
    end

    def initialize(name)
      @name = name.to_sym
      @agents = {}
      @profiles = {}
      @logger = Logger.new($stdout)
      @logger.level = Logger::INFO
      
      # Implicit default configs for the internal components
      @engine_evaluator = RubyLlm::LLMService.new(
        profile_name: 'glm', # fallback default for conditions
        temperature: 0.1, 
        logger: @logger
      )
    end

    # DSL: Config block to define profiles
    def config(&block)
      instance_eval(&block)
    end

    # DSL: Inside config, define a profile
    def profile(name, **kwargs)
      @profiles[name.to_sym] = kwargs
    end

    # DSL: Roster block to define agents
    def roster(&block)
      instance_eval(&block)
    end

    # DSL: Inside roster, define an agent
    def agent(name, **kwargs)
      profile_name = kwargs.delete(:profile) || :default
      
      # If the body has a defined profile hash for this, we extract args,
      # but RubyLlm::Profile actually loads from llm.yml via `profile_name`. 
      # The :profile argument in the DSL maps to the ruby_llm profile name, 
      # unless the user mapped a custom tag in `config`.
      
      # Find mapping in profiles
      mapped_profile = @profiles[profile_name]
      actual_ruby_llm_profile = mapped_profile ? mapped_profile[:provider] || profile_name : profile_name
      
      @agents[name.to_sym] = Agent::Base.new(
        name: name, 
        logger: @logger, 
        profile_name: actual_ruby_llm_profile,
        **kwargs
      )
    end

    # Execution Endpoint: Bind a Soul to this Body and run it
    def animate(soul)
      @logger.info "[Amber::Body::#{@name}] Animating Soul: :#{soul.name} with #{soul.jobs.size} jobs."
      
      # Setup the auto planner if the objective exists
      setup_default_planner_if_missing! if soul.objective
      
      # Run the core concurrent engine loop logic on the Soul's elements
      execute_loop!(soul)
      
      @logger.info "[Amber::Body::#{@name}] Animation Complete. Final Soul State: #{soul.context.snapshot.inspect}"
    end

    private

    def execute_loop!(soul)
      @active_threads = []
      
      loop do
        intercept_dynamic_jobs!(soul)

        pending_jobs = soul.jobs.values.select { |j| j.status == :pending }
        running_jobs = soul.jobs.values.select { |j| j.status == :running }

        @active_threads.reject! { |t| !t.alive? }

        break if pending_jobs.empty? && running_jobs.empty? && @active_threads.empty?

        ready_jobs = pending_jobs.select do |j|
          dependencies_met?(j, soul)
        end

        if ready_jobs.empty? && running_jobs.empty? && @active_threads.empty?
          @logger.error "[Amber::Body::#{@name}] DEADLOCK: No jobs are running and no pending jobs have dependencies met. Terminating."
          break
        end

        ready_jobs.each do |j|
          @logger.info "[Amber::Body::#{@name}] Dispatching Job: :#{j.name}"
          j.instance_variable_set(:@status, :running)
          
          t = Thread.new do
            begin
              # Pass the explicit context to the job execution
              if j.execution_agent
                agent_instance = @agents[j.execution_agent]
                unless agent_instance
                  raise StandardError, "Agent :#{j.execution_agent} not found in this Body's roster."
                end
                
                # Execute AI
                result = agent_instance.execute(soul.context, j.description, run_max_turns: j.max_turns)
                
                # Auto-context writing: write AI yield output to Soul Context
                soul.context.set(j.name, result)
              else
                # Execute Ruby block
                j.execute_ruby!(soul.context)
              end
              @logger.info "[Amber::Body::#{@name}] Finished Job: :#{j.name}"
            rescue StandardError => e
              @logger.error "[Amber::Body::#{@name}] Job :#{j.name} crashed: #{e.message}\n#{e.backtrace.join("\n")}"
              j.instance_variable_set(:@status, :failed)
            ensure
              # Write job completion status to context for `depends_on`
              statuses = soul.context.get(:__amber_job_status) || {}
              statuses[j.name] = j.status
              soul.context.set(:__amber_job_status, statuses)
            end
          end
          
          @active_threads << t
        end

        sleep(0.1) unless ready_jobs.any?
      end
      
      @active_threads.each(&:join)
    end
    


    def intercept_dynamic_jobs!(soul)
      queue = soul.context.get(:__amber_dynamic_jobs)
      return if queue.nil? || queue.empty?

      queue.each do |job_spec|
        job_sym = job_spec[:name].to_sym
        next if soul.jobs.key?(job_sym)

        @logger.info "[Amber::Body] Intercepted Dynamic Job Spawn: :#{job_sym}"
        j = Orchestration::Job.new(job_sym)
        j.instance_variable_set(:@description, job_spec[:objective])
        j.depends_on_ai(job_spec[:condition]) if job_spec[:condition] && !job_spec[:condition].empty?
        
        # Pull max turns
        if job_spec[:max_turns]
          j.instance_variable_set(:@max_turns, job_spec[:max_turns].to_i)
        end

        # Assign generic agent if not specified
        assignee = job_spec[:assignee]
        if assignee
          j.assignee(assignee.to_sym)
        else
          # Fallback generic
          valid_agents = @agents.reject { |k, _v| k == :__amber_planner }.keys
          j.assignee(valid_agents.first) if valid_agents.any?
        end
        
        soul.jobs[job_sym] = j
      end
      
      soul.context.set(:__amber_dynamic_jobs, [])
    end
  end
end
