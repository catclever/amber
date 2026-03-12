require_relative "amber/version"
require_relative "amber/body"
require_relative "amber/soul"
require_relative "amber/sandbox/executor"
require_relative "amber/tool_registry"

# Pre-load all tools in the standard directory structure
Amber::ToolRegistry.load_all!

module Amber
  class Error < StandardError; end
  # The core module exposing Engine.build for DSL
end
