require_relative 'context'
require_relative 'orchestration/job'

module Amber
  class Soul
    attr_reader :name, :context, :jobs, :objective

    def self.define(name = :default, &block)
      soul = new(name)
      soul.instance_eval(&block) if block_given?
      soul
    end

    def initialize(name)
      @name = name.to_sym
      @context = Context.new
      @jobs = {}
      @objective = nil
    end

    # DSL: Inject data directly into the Persistent Context
    def inject_context(hash)
      @context.merge(hash)
    end

    # DSL: Define the overarching ultimate goal for the Planner, or get it
    def objective(text = nil)
      return @objective if text.nil?
      
      @objective = text
      
      # Defining an objective automatically creates an implicit Root Job for the Planner
      j = Orchestration::Job.new(:__amber_root_plan)
      j.description("Goal: #{text}")
      j.assignee(:__amber_planner)
      @jobs[:__amber_root_plan] = j
    end

    # DSL: Define an explicit job
    def job(name, &block)
      j = Orchestration::Job.new(name)
      j.instance_eval(&block) if block_given?
      @jobs[name.to_sym] = j
    end
  end
end
