require_relative '../lib/amber/sandbox/executor'

puts "Testing Amber Sandbox..."
executor = Amber::Sandbox::Executor.new(cpu_limit_sec: 2)

# Test 1: Simple evaluation
puts "\n[Test 1] Simple Math Evaluation"
result = executor.execute("1 + 2 + 3")
puts "Result: #{result} (Expected: 6)"

# Test 2: Local method definitions and return
puts "\n[Test 2] Complex Method"
code = <<~RUBY
  def fib(n)
    return n if n <= 1
    fib(n-1) + fib(n-2)
  end
  fib(10)
RUBY
result = executor.execute(code)
puts "Result: #{result} (Expected: 55)"

# Test 3: AST Block system commands
puts "\n[Test 3] AST Guardrails (Backticks)"
begin
  executor.execute("`echo 'hacked'`")
  puts "FAIL: Should have blocked backticks."
rescue Amber::Sandbox::Executor::SecurityError => e
  puts "SUCCESS: Caught backtick - #{e.message}"
end

puts "\n[Test 4] AST Guardrails (System)"
begin
  executor.execute("system('rm -rf /')")
  puts "FAIL: Should have blocked system."
rescue Amber::Sandbox::Executor::SecurityError => e
  puts "SUCCESS: Caught system - #{e.message}"
end

# Test 5: Infinite Loop Timeout
puts "\n[Test 5] Timeout Handling (2 sec limit)"
begin
  t1 = Time.now
  executor.execute("loop { 1 + 1 }")
  puts "FAIL: Should have timed out."
rescue Amber::Sandbox::Executor::TimeoutError => e
  t2 = Time.now
  puts "SUCCESS: Caught timeout after #{(t2 - t1).round(2)}s - #{e.message}"
end

# Test 6: Workspace Isolation Check
puts "\n[Test 6] Workspace Checking"
result = executor.execute("Dir.pwd")
puts "Result is workspace: #{result.include?('amber_workspace')}"

puts "\nDone!"
