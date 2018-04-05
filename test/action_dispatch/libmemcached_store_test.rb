require_relative '../test_helper'
require_relative 'abstract_unit'
require 'action_dispatch/session/libmemcached_store'

class LibMemcachedStoreTest < ActionDispatch::IntegrationTest
  self.test_order = :sorted if respond_to?(:test_order=)

  class TestController < ActionController::Base
    def no_session_access
      head :ok
    end

    def set_session_value
      session[:foo] = "bar"
      head :ok
    end

    def set_serialized_session_value
      session[:foo] = SessionAutoloadTest::Foo.new
      head :ok
    end

    def get_session_value
      render :text => "foo: #{session[:foo].inspect}"
    end

    def get_session_id
      render :text => "#{request.session_options[:id]}"
    end

    def call_reset_session
      session[:bar]
      reset_session
      session[:bar] = "baz"
      head :ok
    end

    def self._routes
      SharedTestRoutes
    end
  end

  test "setting and getting session value" do
    with_test_route_set do
      get '/set_session_value'
      assert_response :success
      assert cookies['_session_id']

      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: "bar"', response.body
    end
  end

  test "getting nil session value" do
    with_test_route_set do
      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: nil', response.body
    end
  end

  test "getting session value after session reset" do
    with_test_route_set do
      get '/set_session_value'
      assert_response :success
      assert cookies['_session_id']
      session_cookie = cookies.send(:hash_for)['_session_id']

      get '/call_reset_session'
      assert_response :success
      assert_not_equal [], headers['Set-Cookie']

      cookies << session_cookie # replace our new session_id with our old, pre-reset session_id

      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: nil', response.body, "data for this session should have been obliterated from memcached"
    end
  end

  test "getting from nonexistent session" do
    with_test_route_set do
      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: nil', response.body
      assert_nil cookies['_session_id'], "should only create session on write, not read"
    end
  end

  test "setting session value after session reset" do
    with_test_route_set do
      get '/set_session_value'
      assert_response :success
      assert cookies['_session_id']
      session_id = cookies['_session_id']

      get '/call_reset_session'
      assert_response :success
      assert_not_equal [], headers['Set-Cookie']

      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: nil', response.body

      get '/get_session_id'
      assert_response :success
      assert_not_equal session_id, response.body
    end
  end

  test "getting session id" do
    with_test_route_set do
      get '/set_session_value'
      assert_response :success
      assert cookies['_session_id']
      session_id = cookies['_session_id']

      get '/get_session_id'
      assert_response :success
      assert_equal session_id, response.body, "should be able to read session id without accessing the session hash"
    end
  end

  test "deserializes unloaded class" do
    with_test_route_set do
      with_autoload_path "session_autoload_test" do
        get '/set_serialized_session_value'
        assert_response :success
        assert cookies['_session_id']
      end
      with_autoload_path "session_autoload_test" do
        get '/get_session_id'
        assert_response :success
      end
      with_autoload_path "session_autoload_test" do
        get '/get_session_value'
        assert_response :success
        assert_equal 'foo: #<SessionAutoloadTest::Foo bar:"baz">', response.body, "should auto-load unloaded class"
      end
    end
  end

  test "doesnt write session cookie if session id is already exists" do
    with_test_route_set do
      get '/set_session_value'
      assert_response :success
      assert cookies['_session_id']

      get '/get_session_value'
      assert_response :success
      assert_nil headers['Set-Cookie'], "should not resend the cookie again if session_id cookie is already exists"
    end
  end

  test "prevents session fixation" do
    with_test_route_set do
      get '/get_session_value'
      assert_response :success
      assert_equal 'foo: nil', response.body
      session_id = cookies['_session_id']

      reset!

      get '/set_session_value', :_session_id => session_id
      assert_response :success
      assert_not_equal session_id, cookies['_session_id']
    end
  end

  private

  def with_test_route_set
    with_routing do |set|
      set.draw do
        get ':action', :to => TestController
      end

      @app = self.class.build_app(set) do |middleware|
        middleware.use ActionDispatch::Session::LibmemcachedStore, :key => '_session_id'
        middleware.delete "ActionDispatch::ShowExceptions"
      end

      yield
    end
  end

  def with_autoload_path(path)
    path = File.join(File.dirname(__FILE__), "../fixtures", path)
    if ActiveSupport::Dependencies.autoload_paths.include?(path)
      yield
    else
      begin
        ActiveSupport::Dependencies.autoload_paths << path
        yield
      ensure
        ActiveSupport::Dependencies.autoload_paths.reject! {|p| p == path}
        ActiveSupport::Dependencies.clear
      end
    end
  end
end
