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

  def execute(args)
    city = args['city']
    puts "\n[Tool Execution] -> Fetching weather data for #{city}..."
    sleep(1) # Simulate network call
    
    # Return mock data
    "The weather in #{city} is 72 degrees and sunny."
  end
end


# --- 2. Build the Amber Engine DSL ---
puts "Building Amber Agent DSL..."

engine = Amber::Engine.build do
  # Shared Context
  environment user_query: "What's the weather like in Tokyo today?",
              weather_result: nil

  # Define the Agent and load our custom tool
  agent :weather_bot, 
        profile_name: 'openai', 
        system_prompt: "You are a helpful weather assistant.",
        tools: [WeatherLookupTool]

  # Job 1: Check if the user is actually asking about weather
  job :analyze_query do
    depends_on_ai "Does the `user_query` in context ask about the weather?"
    
    action "Find the weather for the user and save it to `weather_result`."
    executed_by_agent :weather_bot
  end
  
  # Job 2: Wait for Job 1 to finish, then print the result
  job :print_result do
    depends_on { |ctx| ctx.get(:weather_result) != nil }
    
    action "Print the final weather context"
    executed_by do |ctx|
      puts "\n=== FINAL RESULT ==="
      puts "User Query: #{ctx.get(:user_query)}"
      puts "AI Answer: #{ctx.get(:weather_result)}"
      puts "====================\n"
    end
  end
end

# --- 3. Execute ---
puts "\nExecuting Amber Engine Integration Test..."
engine.run!
puts "\nDone!"
