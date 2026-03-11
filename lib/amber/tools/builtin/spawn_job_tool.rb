require_relative '../base_tool'

module Amber
  module Tool
    class SpawnJob < Base
      name 'spawn_job'
      description "Dynamically spawn a new executing Job into the Amber State Machine Engine to handle a specific sub-task. If you are the Planner, use this tool to create multiple jobs, and then YOU MUST call 'send_message' to yield control so the engine can run your spawned jobs."
      parameters(
        type: 'object',
        properties: {
          job_name: { type: 'string', description: 'A unique short snake_case name for the new job, e.g., read_logs.' },
          objective: { type: 'string', description: 'What this job should accomplish (its prompt/action instructions).' },
          depends_on_ai: { type: 'string', description: 'Optional. A natural language condition evaluating the Shared Context that MUST be TRUE before this job triggers.' },
          max_turns: { type: 'integer', description: 'Optional. Maximum number of LLM reasoning turns this job is allowed to run. Default is 30, increase it for complex tasks.' }
        },
        required: ['job_name', 'objective']
      )

      def execute(args)
        queue = @context.get(:__amber_dynamic_jobs) || []
        
        new_job_definition = {
          name: args['job_name'],
          objective: args['objective'],
          condition: args['depends_on_ai'],
          max_turns: args['max_turns']
        }
        
        queue << new_job_definition
        @context.set(:__amber_dynamic_jobs, queue)
        
        "Successfully scheduled job :#{args['job_name']} in the Engine. If you are done planning, YOU MUST call 'send_message' now to yield control."
      end
    end
  end
end
