require_relative 'context'
require_relative 'orchestration/job'
require_relative 'agent/base'
require 'logger'

module Amber
  class Engine
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
      
      # For now, we use a simple synchronous polling loop to simulate parallelism and waiting.
      # In future iterations, this will be swapped to truly concurrent threaded execution.
      
      loop do
        pending_jobs = @jobs.values.select { |j| j.status == :pending }
        running_jobs = @jobs.values.select { |j| j.status == :running }

        break if pending_jobs.empty? && running_jobs.empty?

        ready_jobs = pending_jobs.select do |j|
          dependencies_met?(j)
        end

        if ready_jobs.empty? && running_jobs.empty?
          @logger.error "[Amber] DEADLOCK: No jobs are running and no pending jobs have their dependencies met. Terminating."
          break
        end

        ready_jobs.each do |j|
          @logger.info "[Amber] Dispatching Job: :#{j.name}"
          j.execute!(@context)
          @logger.info "[Amber] Finished Job: :#{j.name} with status: #{j.status}"
        end

        sleep(0.1) unless ready_jobs.any?
      end

      @logger.info "[Amber] Engine Run Complete. Final Context: #{@context.snapshot.inspect}"
    end

    private

    def dependencies_met?(job)
      # 1. Check formal logic dependencies evaluating against context
      formal_met = job.dependencies.all? do |condition_block|
        condition_block.call(@context)
      end
      return false unless formal_met

      # 2. Check Semantic (AI) dependencies against context
      ai_met = job.ai_dependencies.all? do |ai_requirement|
        evaluate_condition_via_llm?(ai_requirement)
      end
      return false unless ai_met

      true
    end

    def evaluate_condition_via_llm?(requirement)
      @logger.debug "[Amber] AI evaluating dependency: '#{requirement}'"
      
      prompt = <<~PROMPT
        You are a binary logic evaluator for a State Machine Context.
        Analyze the following Shared Context data and determine if the required condition is met.
        
        Shared Context:
        #{@context.snapshot.to_json}
        
        Condition:
        "#{requirement}"
        
        Respond with ONLY exactly 'true' or 'false', with no punctation, reasoning, or markdown.
      PROMPT

      response = @engine_evaluator.call(prompt)
      result = response.content.to_s.strip.downcase

      @logger.info "[Amber] AI Evaluated '#{requirement}': #{result}"
      
      result == 'true'
    rescue StandardError => e
      @logger.error "[Amber] Failed to evaluate AI condition '#{requirement}': #{e.message}"
      false
    end
  end
end
