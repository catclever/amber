require_relative '../lib/amber'

# ======================================================================
# Advanced Amber Example: Auto-Analyzing a Git Repository
# This example demonstrates:
# 1. Defining Tools (with configurable Sandbox limits)
# 2. Defining Agents
# 3. Defining Jobs (Context-driven orchestration)
# 4. LLM dynamically designing and injecting NEW Jobs at runtime
# ======================================================================

# --- 1. Define Tools with Configurable Sandbox Arguments ---
# We define a custom ShellRunner Tool that runs code in the Amber Sandbox.
class GitShellTool < Amber::Tool::Base
  name 'run_shell_in_git_repo'
  description 'Execute safe bash-like Ruby system commands to explore the repo (e.g. Dir.glob, File.read)'
  
  parameters(
    type: 'object',
    properties: {
      ruby_code: { type: 'string', description: 'Ruby code to evaluate, e.g., File.read("README.md")' }
    },
    required: ['ruby_code']
  )

  # Support passing sandbox parameters during configuration!
  def self.configure_sandbox(memory_mb:, cpu_sec:)
    @sandbox_config = { memory_limit_mb: memory_mb, cpu_limit_sec: cpu_sec }
  end

  def self.sandbox_config
    @sandbox_config || { memory_limit_mb: 100, cpu_limit_sec: 5 }
  end

  def execute(args)
    config = self.class.sandbox_config
    # Initialize the sandbox with the custom parameters defined in the DSL
    executor = Amber::Sandbox::Executor.new(**config)
    
    begin
      # In real usage, we would Dir.chdir into the actual target repo here, 
      # but the Sandbox creates an isolated tmp workspace for safety.
      result = executor.execute(args['ruby_code'])
      "Execution output: #{result}"
    rescue => e
      "Error: #{e.message}"
    end
  end
end

# A special tool that allows an Agent to dynamically create NEW Jobs in the engine!
class JobDesignerTool < Amber::Tool::Base
  name 'design_new_job'
  description 'Dynamically append a new Sub-Job to the Engine pipeline by modifying the Context'
  parameters(
    type: 'object',
    properties: {
      job_name: { type: 'string', description: 'Name of the new job to create' },
      objective: { type: 'string', description: 'The goal of this new job' }
    },
    required: ['job_name', 'objective']
  )

  def execute(args)
    # 5. LLM automatically designs new jobs
    # By pushing a new plan to the array, the Engine (which watches this array)
    # can trigger a dynamic meta-job loop.
    plan = @context.get(:dynamic_plan) || []
    plan << args
    @context.set(:dynamic_plan, plan)
    "Successfully added job #{args['job_name']} to the dynamic plan. The Engine will pick it up."
  end
end

# --- 2. Build the Amber Engine ---
engine = Amber::Engine.build do
  
  # Configure Sandbox limits for this specific tool globally before attaching to agents
  GitShellTool.configure_sandbox(memory_mb: 512, cpu_sec: 15)

  # 1. State/Context Definition (Weak schema, flexible keys)
  environment target_repo: '/Users/kael/workbench/ruby_lab/amber',
              repo_summary: nil,
              dynamic_plan: []

  # 3. Define Agents
  agent :scout, 
        profile_name: 'glm2', # User's default API config
        system_prompt: "You are a Git Repo Scout. Use tools to look at the repo's files.",
        tools: [GitShellTool]
        
  agent :architect, 
        profile_name: 'glm2',
        system_prompt: "You are a Staff Engineer. Based on repo summaries, design a breakdown of sub-jobs to analyze it deeper.",
        tools: [JobDesignerTool]

  # 4. Define Execution Workflow (Jobs)
  
  # Job A: Read the Repo (Triggered instantly because condition is met)
  job :initial_recon do
    depends_on { |ctx| ctx.get(:target_repo) != nil && ctx.get(:repo_summary) == nil }
    action "Read the README.md and list the files in the repo, then summarize what this project is. Submit summary to `repo_summary`."
    executed_by_agent :scout
  end

  # Job B: Architect designs further jobs (Triggered only after Job A finishes)
  job :design_analysis_plan do
    depends_on { |ctx| ctx.get(:repo_summary) != nil && ctx.get(:dynamic_plan).empty? }
    action "Read the `repo_summary` and use your JobDesignerTool to plan 2 specific code review tasks for this repo. Then submit 'Done' to `architecture_planned`."
    executed_by_agent :architect
  end
  
  # Job C: Watchdog that executes the new dynamic jobs LLM created!
  job :execute_dynamic_plan do
    # Triggered when LLM has populated the dynamic_plan array
    depends_on { |ctx| ctx.get(:dynamic_plan) != nil && !ctx.get(:dynamic_plan).empty? }
    
    action "Print dynamic plan execution"
    executed_by do |ctx|
      plan = ctx.get(:dynamic_plan)
      puts "\n\n🚀 [DYNAMIC EXECUTION ENGINE] Intercepted new jobs designed by LLM:"
      plan.each do |dynamic_job|
        puts "   -> Auto-Spawning Job [:#{dynamic_job['job_name']}] - Objective: #{dynamic_job['objective']}"
        # In a full Amber implementation, the Engine would dynamically instantiate 
        # an Amber::Orchestration::Job object here and append it to the active pool!
      end
      
      # Clear it to prevent infinite loops in the test
      ctx.set(:dynamic_plan, [])
    end
  end
end

if __FILE__ == $0
  puts "Running Git Repo Reader Example..."
  engine.run!
end
