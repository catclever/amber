require_relative '../lib/amber'

# Ensure you have your llm.yml or ENV variables setup for 'openai' profile
puts "Building Amber Agent DSL..."

engine = Amber::Engine.build do
  # 1. Global Context
  environment prompt: "Can you analyze this string 'Hello World' and reverse it?"

  # 2. Define an Agent with an LLM profile
  agent :analyzer, profile_name: 'glm2', system_prompt: "You are a String analysis AI."

  job :request_analysis do
    action "Pass the user's string to the Agent to analyze and reverse it."
    
    # Needs to ensure the prompt is loaded into memory
    depends_on { |ctx| ctx.get(:prompt) != nil }
    
    # Assign predefined agent execution
    executed_by_agent :analyzer
  end
end

puts "\nExecuting Amber Engine..."
engine.run!
puts "\nDone!"
