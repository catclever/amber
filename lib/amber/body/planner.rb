module Amber
  class Body
    module Planner
      # Called by the Evaluator when it detects a missing unhandled semantic gap
      def spawn_dynamic_job_for_missing_requirement(soul, goal)
        queue = soul.context.get(:__amber_dynamic_jobs) || []
        job_sym = :"auto_solve_#{Time.now.to_i}_#{rand(1000)}"
        
        queue << {
          name: job_sym.to_s,
          objective: "Resolve missing Context Requirement: #{goal}. Break this down using your spawn_job tool, or solve it yourself and use update_context tool to save it.",
          condition: nil
        }
        soul.context.set(:__amber_dynamic_jobs, queue)
        
        setup_default_planner_if_missing!
      end

      private

      def setup_default_planner_if_missing!
        unless @agents.key?(:__amber_planner)
          evaluator_profile = @engine_evaluator.instance_variable_get(:@profile_name) || 'glm'
          agent :__amber_planner, 
                profile_name: evaluator_profile, 
                max_turns: 50,
                system_prompt: "You are the primary Amber Auto-Planner. Break down complex goals into execution steps using your `spawn_job` tool. Assign them to generic worker agents. Do not stop until all components of the goal are planned. Use update_context to return important facts.",
                tools: [:spawn_job]
        end
      end
    end
  end
end
