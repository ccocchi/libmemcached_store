require 'active_support'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/module/attribute_accessors'
require 'action_controller'
require 'action_dispatch/routing'
if ActionPack::VERSION::MAJOR >= 4
  require 'rack/head'
else
  require 'action_dispatch/middleware/head'
end
require 'action_dispatch/testing/assertions'
require 'action_dispatch/testing/test_process'
require 'action_dispatch/testing/integration'

SharedTestRoutes = ActionDispatch::Routing::RouteSet.new

class RoutedRackApp
  attr_reader :routes

  def initialize(routes, &blk)
    @routes = routes
    @stack = ActionDispatch::MiddlewareStack.new(&blk).build(@routes)
  end

  def call(env)
    @stack.call(env)
  end
end

class ActionDispatch::IntegrationTest < ActiveSupport::TestCase
  def self.build_app(routes = nil)
    RoutedRackApp.new(routes || ActionDispatch::Routing::RouteSet.new) do |middleware|
      if defined?(ActionDispatch::PublicExceptions)
        middleware.use ActionDispatch::ShowExceptions, ActionDispatch::PublicExceptions.new("/dev/null")
        middleware.use ActionDispatch::DebugExceptions
      else
        middleware.use ActionDispatch::ShowExceptions
      end
      middleware.use ActionDispatch::Callbacks
      if defined?(ActionDispatch::Http::Parameters::ParseError)
        middleware.use ActionDispatch::Http::Parameters::ParseError
      else
        middleware.use ActionDispatch::ParamsParser
      end
      middleware.use ActionDispatch::Cookies
      middleware.use ActionDispatch::Flash
      if ActionPack::VERSION::MAJOR >= 4
        middleware.use Rack::Head
      else
        middleware.use ActionDispatch::Head
      end
      yield(middleware) if block_given?
    end
  end
end
