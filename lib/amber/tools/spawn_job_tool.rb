require_relative 'base_tool'

module Amber
  module Tool
    class SpawnJob < Base
      name 'spawn_job'
      description 'Dynamically spawn a new executing Job into the Amber State Machine Engine to handle a specific sub-task.'
      parameters(
        type: 'object',
        properties: {
          job_name: { type: 'string', description: 'A unique short snake_case name for the new job, e.g., read_logs.' },
          objective: { type: 'string', description: 'What this job should accomplish (its prompt/action instructions).' },
          depends_on_ai: { type: 'string', description: 'Optional. A natural language condition evaluating the Shared Context that MUST be TRUE before this job triggers.' }
        },
        required: ['job_name', 'objective']
      )

      def execute(args)
        queue = @context.get(:__amber_dynamic_jobs) || []
        
        new_job_definition = {
          name: args['job_name'],
          objective: args['objective'],
          condition: args['depends_on_ai']
        }
        
        queue << new_job_definition
        @context.set(:__amber_dynamic_jobs, queue)
        
        "Successfully scheduled job :#{args['job_name']} in the Engine."
      end
    end
  end
end
