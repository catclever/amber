require_relative '../lib/amber'

# --- 1. Define a Custom Tool ---
class WeatherLookupTool < Amber::Tool::Base
  name 'get_current_weather'
  description 'Lookup the current weather for a given city.'
  parameters(
    type: 'object',
    properties: {
      city: { type: 'string', description: 'The name of the city, e.g., Tokyo' }
    },
    required: ['city']
  )

  def execute(args, context = nil)
    city = args['city']
    puts "\n[Tool Execution] -> Fetching weather data for #{city}..."
    sleep(1) # Simulate network call
    
    # Return mock data
    "The weather in #{city} is 72 degrees and sunny."
  end
end


# --- 2. Build the Amber Body & Soul DSL ---
puts "Building Amber Agent DSL..."

body = Amber::Body.define :weather_agency do
  config do
    profile :glm, provider: :glm, model: 'glm-5', tags: [:default, :planner]
  end

  roster do
    # Define the Agent and load our custom tool
    agent :weather_bot, 
          profile: :glm, 
          system_prompt: "You are a helpful weather assistant.",
          tools: [WeatherLookupTool]
  end
end

soul = Amber::Soul.define :check_weather_flow do
  # Shared Context
  inject_context user_query: "What's the weather like in Tokyo today?",
                 weather_result: nil

  # Job 1: Check if the user is actually asking about weather
  job :analyze_query do
    depends_on_ai "Does the `user_query` in context ask about the weather?"
    
    description "Find the weather for the user and save it to `weather_result`."
    assignee :weather_bot
  end
  
  # Job 2: Wait for Job 1 to finish, then print the result
  job :print_result do
    depends_on { |ctx| ctx.get(:weather_result) != nil }
    
    description "Print the final weather context"
    execute do |ctx|
      puts "\n=== FINAL RESULT ==="
      puts "User Query: #{ctx.get(:user_query)}"
      puts "AI Answer: #{ctx.get(:weather_result)}"
      puts "====================\n"
    end
  end
end

# --- 3. Execute ---
puts "\nExecuting Amber Body Integration Test..."
body.animate(soul)
puts "\nDone!"
