require 'json'

module Amber
  class Body
    module Evaluator
      def dependencies_met?(job, soul)
        # 1. Check formal logic dependencies evaluating against context
        formal_met = job.dependencies.all? do |condition_block|
          condition_block.call(soul.context)
        end
        return false unless formal_met

        # 2. Check Semantic (AI) dependencies against context
        ai_met = job.ai_dependencies.all? do |ai_requirement|
          evaluate_condition_via_llm?(ai_requirement, job, soul)
        end
        return false unless ai_met

        true
      end

      private

      def evaluate_condition_via_llm?(requirement, for_job, soul)
        @logger.debug "[Amber] AI evaluating dependency: '#{requirement}' for Job :#{for_job.name}"
        
        prompt = <<~PROMPT
          You are a logic evaluator for an Agentic State Machine.
          Analyze the following Shared Context data against the required Condition.
          
          Shared Context:
          #{soul.context.snapshot.to_json}
          
          Condition:
          "#{requirement}"
          
          Task: Look at the Shared Context. Does it already contain the information or state required by the Condition?
          
          Output JSON ONLY based on these rules:
          1. If the requested information or state is fully present in the Context, output: {"status": "true"}
          2. If the information is NOT present, BUT it looks like a simple factual piece of data (e.g., waiting for an API result or a specific user input), output: {"status": "false"}
          3. If the information is NOT present, AND it implies a complex unhandled task/action (e.g. "All IO info analyzed", "A design spec is created"), output: {"status": "missing_task", "suggested_goal": "The required action to fulfill the condition"}

          JSON ONLY. No markdown formatted blocks, no apologies.
        PROMPT

        response = @engine_evaluator.call(prompt)
        result_text = response.content.to_s.strip
        result_text = result_text.gsub(/^```json/, '').gsub(/```$/, '').strip # Strip markdown if present
        
        result = JSON.parse(result_text)

        case result['status']
        when 'true'
          @logger.info "[Amber] AI Evaluated '#{requirement}': true"
          return true
        when 'missing_task'
          @logger.info "[Amber] AI Evaluated '#{requirement}': missing_task. Spawning auto-planner for: #{result['suggested_goal']}"
          # Automatically trigger the Planner to resolve this unhandled complex missing task!
          spawn_dynamic_job_for_missing_requirement(soul, result['suggested_goal'])
          return false # Not met yet, let the planner work on it
        else
          @logger.info "[Amber] AI Evaluated '#{requirement}': false"
          return false
        end
      rescue StandardError => e
        @logger.error "[Amber] Failed to evaluate AI condition '#{requirement}': #{e.message}. Raw output: #{result_text}"
        false
      end
    end
  end
end
