# encoding: utf-8

require_relative '../test_helper'
require 'memcached'
require 'active_support'
require 'active_support/core_ext/module/aliasing'
require 'active_support/core_ext/object/duplicable'
require 'active_support/cache/libmemcached_store'

# Make it easier to get at the underlying cache options during testing.
ActiveSupport::Cache::LibmemcachedStore.class_eval do
  def client_options
    @cache.options
  end
end

module Rails
  def self.logger
    Logger.new(StringIO.new)
  end
end

describe ActiveSupport::Cache::LibmemcachedStore do
  class MockUser
    def cache_key
      'foo'
    end
  end

  before do
    @cache = ActiveSupport::Cache.lookup_store(:libmemcached_store, expires_in: 60)
    @cache.clear
    @cache.silence!
  end

  describe "cache store behavior" do
    def really_long_keys_test
      key = "a" * 251
      assert @cache.write(key, "bar")
      assert_equal "bar", @cache.read(key)
      assert_equal "bar", @cache.fetch(key)
      assert_nil @cache.read("#{key}x")
      assert_equal({key => "bar"}, @cache.read_multi(key))
      assert @cache.delete(key)
      refute @cache.exist?(key)
      assert @cache.write(key, '2', :raw => true)
      assert_equal 3, @cache.increment(key)
      assert_equal 2, @cache.decrement(key)
    end

    def listen_to_instrumentation
      if ActiveSupport::VERSION::MAJOR == 3
        old, ActiveSupport::Cache::Store.instrument = ActiveSupport::Cache::Store.instrument, true
      end
      called = []
      key = //
      ActiveSupport::Notifications.subscribe(key) do |*args|
        args[1..3] = [] # ignore timestamps
        called << args
      end
      yield
      called
    ensure
      ActiveSupport::Notifications.unsubscribe(key)
      if ActiveSupport::VERSION::MAJOR == 3
        ActiveSupport::Cache::Store.instrument = old
      end
    end

    it "fetch_without_cache_miss" do
      @cache.write('foo', 'bar')
      @cache.expects(:write_entry).never
      assert_equal 'bar', @cache.fetch('foo') { 'baz' }
    end

    it "fetch_with_cache_miss" do
      @cache.expects(:write_entry).with('foo', 'baz', nil)
      assert_equal 'baz', @cache.fetch('foo') { 'baz' }
    end

    it "fetch_with_forced_cache_miss" do
      @cache.write('foo', 'bar')
      @cache.expects(:read_entry).never
      @cache.expects(:write_entry).with('foo', 'baz', force: true)
      assert_equal 'baz', @cache.fetch('foo', force: true) { 'baz' }
    end

    it "fetch_with_cached_false" do
      @cache.write('foo', false)
      refute @cache.fetch('foo') { raise }
    end

    it "fetch_with_raw_object" do
      o = Object.new
      o.instance_variable_set :@foo, 'bar'
      assert_equal o, @cache.fetch('foo', raw: true) { o }
    end

    it "fetch_with_cache_key" do
      u = MockUser.new
      @cache.write(u.cache_key, 'bar')
      assert_equal 'bar', @cache.fetch(u) { raise }
    end

    it "should_read_and_write_strings" do
      assert @cache.write('foo', 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "should_read_and_write_hash" do
      assert @cache.write('foo', { a: 'b' })
      assert_equal({ a: 'b' }, @cache.read('foo'))
    end

    it "should_read_and_write_integer" do
      assert @cache.write('foo', 1)
      assert_equal 1, @cache.read('foo')
    end

    it "should_read_and_write_nil" do
      assert @cache.write('foo', nil)
      assert_nil @cache.read('foo')
    end

    it "should_read_and_write_false" do
      assert @cache.write('foo', false)
      assert_equal false, @cache.read('foo')
    end

    it "read_and_write_compressed_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1)
      assert_equal 'bar', @cache.read('foo')
    end

    it "write_should_overwrite" do
      @cache.write('foo', 'bar')
      @cache.write('foo', 'baz')
      assert_equal 'baz', @cache.read('foo')
    end

    it "write_compressed_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1, :raw => true)
      assert_equal Zlib::Deflate.deflate('bar'), @cache.instance_variable_get(:@cache).get('foo', false)
    end

    it "read_miss" do
      assert_nil @cache.read('foo')
    end

    it "read_should_return_a_different_object_id_each_time_it_is_called" do
      @cache.write('foo', 'bar')
      refute_equal @cache.read('foo').object_id, @cache.read('foo').object_id
    end

    describe "#read_multi" do
      it "reads multiple" do
        @cache.write('foo', 'bar')
        @cache.write('fu', 'baz')
        @cache.write('fud', 'biz')
        assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
      end

      it "reads with array" do
        @cache.write('foo', 'bar')
        @cache.write('fu', 'baz')
        assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi(['foo', 'fu']))
      end

      it "reads with raw" do
        @cache.write('foo', 'bar', :raw => true)
        @cache.write('fu', 'baz', :raw => true)
        assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
      end

      it "reads with compress" do
        @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1)
        @cache.write('fu', 'baz', :compress => true, :compress_threshold => 1)
        assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
      end

      it "instruments" do
        called = listen_to_instrumentation do
          @cache.read_multi('foo', 'fu')
        end
        called.must_equal [["cache_read_multi.active_support", {:key=>["foo", "fu"]}]]
      end
    end

    it "cache_key" do
      o = MockUser.new
      @cache.write(o, 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "param_as_cache_key" do
      obj = Object.new
      def obj.to_param
        'foo'
      end
      @cache.write(obj, 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "array_as_cache_key" do
      @cache.write([:fu, 'foo'], 'bar')
      assert_equal 'bar', @cache.read('fu/foo')
    end

    it "hash_as_cache_key" do
      @cache.write({:foo => 1, :fu => 2}, 'bar')
      assert_equal 'bar', @cache.read('foo=1/fu=2')
    end

    it "keys_are_case_sensitive" do
      @cache.write('foo', 'bar')
      assert_nil @cache.read('FOO')
    end

    it "keys_with_spaces" do
      assert_equal 'baz', @cache.fetch('foo bar') { 'baz' }
    end

    it "can write frozen keys" do
      key = 'foo bar'.freeze
      @cache.write(key, 1)
      @cache.read(key).must_equal 1
    end

    describe "#exist?" do
      it "is true when key exists" do
        @cache.write('foo', 'bar')
        assert @cache.exist?('foo')
      end

      it "is false when key does not exist" do
        refute @cache.exist?('bar')
      end

      it "is true when key is set to false" do
        @cache.write('foo', false)
        assert @cache.exist?('foo')
      end

      it "instruments" do
        called = listen_to_instrumentation do
          @cache.exist?('foo')
        end
        called.must_equal [["cache_exist?.active_support", {:key=>"foo", :exception=>["Memcached::NotFound", "Memcached::NotFound"]}]]
      end
    end

    describe "#delete" do
      it "deletes and returns true" do
        @cache.write('foo', 'bar')
        assert @cache.exist?('foo')
        assert @cache.delete('foo')
        refute @cache.exist?('foo')
      end

      it "returns false if key does not exist" do
        @cache.expects(:log_error).never
        refute @cache.exist?('foo')
        refute @cache.delete('foo')
      end

      it "instruments" do
        called = listen_to_instrumentation do
          @cache.delete('foo')
        end
        called.must_equal [["cache_delete.active_support", {:key=>"foo"}]]
      end
    end

    it "store_objects_should_be_immutable" do
      @cache.write('foo', 'bar')
      @cache.read('foo').gsub!(/.*/, 'baz')
      assert_equal 'bar', @cache.read('foo')
    end

    it "original_store_objects_should_not_be_immutable" do
      bar = 'bar'
      @cache.write('foo', bar)
      assert_equal 'baz', bar.gsub!(/r/, 'z')
    end

    it "crazy_key_characters" do
      crazy_key = "#/:*(<+=> )&$%@?;'\"\'`~-"
      assert @cache.write(crazy_key, "1", :raw => true)
      assert_equal "1", @cache.read(crazy_key)
      assert_equal "1", @cache.fetch(crazy_key)
      assert @cache.delete(crazy_key)
      refute @cache.exist?(crazy_key)
      assert_equal "2", @cache.fetch(crazy_key, :raw => true) { "2" }
      assert_equal 3, @cache.increment(crazy_key)
      assert_equal 2, @cache.decrement(crazy_key)
    end

    it "really_long_keys" do
      really_long_keys_test
    end

    it "really_long_keys_with_namespace" do
      @cache = ActiveSupport::Cache.lookup_store(:libmemcached_store, :expires_in => 60, :namespace => 'namespace')
      @cache.silence!
      really_long_keys_test
    end

    it "really_long_keys_with_client_prefix" do
      @cache = ActiveSupport::Cache.lookup_store(:libmemcached_store, :expires_in => 60, :client => { :prefix_key => 'namespace', :prefix_delimiter => ':'})
      @cache.silence!
      really_long_keys_test
    end

    describe "#clear" do
      it "clears" do
        @cache.write("foo", "bar")
        @cache.clear
        assert_nil @cache.read("foo")
      end

      it "ignores options" do
        @cache.write("foo", "bar")
        @cache.clear(:some_option => true)
        assert_nil @cache.read("foo")
      end

      it "instruments" do
        called = listen_to_instrumentation do
          @cache.clear
        end
        called.must_equal [["cache_clear.active_support", {:key=>"*"}]]
      end
    end
  end

  describe "compression" do
    it "read_and_write_compressed_small_data" do
      @cache.write('foo', 'bar', :compress => true)
      raw_value = @cache.send(:read_entry, 'foo', {})
      assert_equal 'bar', @cache.read('foo')
      value = Marshal.load(raw_value) rescue raw_value
      assert_equal 'bar', value
    end

    it "read_and_write_compressed_large_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 2)
      raw_value = @cache.send(:read_entry, 'foo', :raw => true)
      assert_equal 'bar', @cache.read('foo')
      assert_equal 'bar', Marshal.load(raw_value)
    end
  end

  describe "increment / decrement" do
    it "increment" do
      @cache.write('foo', '1', :raw => true)
      assert_equal 1, @cache.read('foo').to_i
      assert_equal 2, @cache.increment('foo')
      assert_equal 2, @cache.read('foo').to_i
      assert_equal 3, @cache.increment('foo')
      assert_equal 3, @cache.read('foo').to_i
    end

    it "decrement" do
      @cache.write('foo', '3', :raw => true)
      assert_equal 3, @cache.read('foo').to_i
      assert_equal 2, @cache.decrement('foo')
      assert_equal 2, @cache.read('foo').to_i
      assert_equal 1, @cache.decrement('foo')
      assert_equal 1, @cache.read('foo').to_i
    end

    it "increment_decrement_non_existing_keys" do
      @cache.expects(:log_error).never
      assert_nil @cache.increment('foo')
      assert_nil @cache.decrement('bar')
    end
  end

  it "is a cache store" do
    assert_kind_of ActiveSupport::Cache::LibmemcachedStore, @cache
  end

  it "sets server addresses to nil if none are given" do
    assert_equal [], @cache.addresses
  end

  it "set custom server addresses" do
    store = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost', '192.168.1.1'
    assert_equal %w(localhost 192.168.1.1), store.addresses
  end

  it "enables consistent ketema hashing by default" do
    assert_equal :consistent_ketama, @cache.client_options[:distribution]
  end

  it "does not enable non blocking io by default" do
    assert_equal false, @cache.client_options[:no_block]
  end

  it "does not enable server failover by default" do
    assert_nil @cache.client_options[:failover]
  end

  it "allows configuration of custom options" do
    options = { client: { tcp_nodelay: true, distribution: :modula } }

    store = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost', options

    assert_equal :modula, store.client_options[:distribution]
    assert_equal true, store.client_options[:tcp_nodelay]
  end

  it "allows mute and silence" do
    cache = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost'
    cache.mute do
      assert cache.write('foo', 'bar')
      assert_equal 'bar', cache.read('foo')
    end
    refute cache.silence?
    cache.silence!
    assert cache.silence?
  end

  describe "#fetch with :race_condition_ttl" do
    let(:options) { {:expires_in => 1, :race_condition_ttl => 5} }

    def fetch(&block)
      @cache.fetch("unknown", options, &block)
    end

    after do
      Thread.list.each { |t| t.exit unless t == Thread.current }
    end

    it "works like a normal fetch" do
      fetch { 1 }.must_equal 1
    end

    it "does not blow up when used with nil expires_in" do
      options[:expires_in] = nil
      fetch { 1 }.must_equal 1
    end

    it "does not blow up when used without expires_in" do
      options.delete(:expires_in)
      fetch { 2 }.must_equal 2
    end

    it "keeps a cached value even if the cache expires" do
      fetch { 1 } # fill it

      future = Time.now + 3 * 60
      Time.stubs(:now).returns future

      t = Thread.new do
        sleep 0.1
        fetch { raise } # 3rd fetch -> read expired value
      end

      fetch { sleep 0.2; 2 }.must_equal 2 # 2nd fetch -> takes time to generate but returns correct value
      fetch { 3 }.must_equal 2 # 4th fetch still correct value
      t.value.must_equal 1
    end

    it "can be read by a normal read" do
      fetch { 1 }
      @cache.read("unknown").must_equal 1
    end

    it "can be read by a normal read_multi" do
      fetch { 1 }
      @cache.read_multi("unknown").must_equal "unknown" => 1
    end

    it "can be read by a normal fetch" do
      fetch { 1 }
      @cache.fetch("unknown") { 2 }.must_equal 1
    end

    it "can write to things that get fetched" do
      fetch { 1 }
      @cache.write "unknown", 2
      fetch { 1 }.must_equal 2
    end
  end
end
