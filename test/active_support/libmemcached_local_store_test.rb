require_relative '../test_helper'
require 'memcached'
require 'active_support'
require 'active_support/core_ext/module/aliasing'
require 'active_support/core_ext/object/duplicable'
require 'active_support/cache/libmemcached_local_store'

describe ActiveSupport::Cache::LibmemcachedLocalStore do
  # it with and without local cache
  def self.it_wawo(description, &block)
    it "#{description} with local cache" do
      @cache.with_local_cache do
        instance_eval(&block)
      end
    end

    it "#{description} without locale cache" do
      instance_eval(&block)
    end
  end

  before do
    @cache = ActiveSupport::Cache.lookup_store(:libmemcached_local_store, expires_in: 60)
    @cache.silence!
    @cache.clear
    @memcache = @cache.instance_variable_get(:@cache)
  end

  it_wawo "can read and write" do
    @cache.write 'x', 1
    @cache.read('x').must_equal 1
  end

  it_wawo "can read raw" do
    @cache.write 'x', 1, raw: true
    @cache.read('x').must_equal "1"
  end

  it_wawo "can read raw when written with raw" do
    @cache.write 'x', 1, raw: true
    @cache.read('x', raw: true).must_equal "1"
  end

  it_wawo "can read normal as raw" do
    @cache.write 'x', 1
    @cache.read('x', raw: true).must_equal "\x04\bi\x06"
  end

  it_wawo "can increment" do
    @cache.write 'x', 0, raw: true
    @cache.increment 'x', 1
    @cache.increment 'x', 1
    @cache.read('x').must_equal "2"
  end

  it_wawo "can increment with default" do
    @cache.write 'x', 0, raw: true
    @cache.increment 'x'
    @cache.read('x').must_equal "1"
  end

  it_wawo "can decrement" do
    @cache.write 'x', 3, raw: true
    @cache.decrement 'x', 1
    @cache.decrement 'x', 1
    @cache.read('x').must_equal "1"
  end

  it_wawo "can decrement with default" do
    @cache.write 'x', 3, raw: true
    @cache.decrement 'x'
    @cache.read('x').must_equal "2"
  end

  describe 'reading nil with locale store' do
    it "caches nil in local cache" do
      @cache.with_local_cache do
        @memcache.expects(get: nil)
        @cache.read('xxx').must_be_nil
        @memcache.expects(:get).never
        @cache.read('xxx').must_be_nil
      end
    end

    it "does not call local_cache multiple times" do
      @cache.with_local_cache do
        @cache.expects(local_cache: @cache.send(:local_cache))
        @cache.read('xxx').must_be_nil
      end
    end
  end

  describe "read_multi" do
    it_wawo "can read multi" do
      @cache.write 'x', 3
      @cache.read_multi('x', 'y').must_equal("x" => 3)
    end

    it "uses remote cache when local cache is missing keys" do
      @cache.write('a', 1)

      @cache.with_local_cache do
        @cache.write('b', 2)
        @memcache.expects(:get).with(['a'], false, true).returns([{ 'a' => 1 }, {}])
        assert_equal({ 'a' => 1, 'b' => 2 }, @cache.read_multi('a', 'b'))
      end
    end

    it "stores remote cache results in local cache" do
      @cache.with_local_cache do
        @memcache.expects(:get).with(['a', 'b'], false, true).returns([{ 'a' => 1 }, {}])
        @cache.read_multi('a', 'b').must_equal 'a' => 1
        @cache.read_multi('a', 'b').must_equal 'a' => 1 # does not call remote cache at all
      end
    end

    it "does not return unfound keys" do
      @cache.with_local_cache do
        @memcache.expects(:get).with(['a'], false, true).returns([{}, {}])
        @cache.read_multi('a').must_equal({})
      end
    end

    it "reads too long keys" do
      key = 'a' * 999
      @cache.write key, 1
      @cache.with_local_cache do
        @memcache.expects(:get).with(anything, false, true).returns([{}, {}])
        @cache.read_multi(key).must_equal({})
      end
    end

    it "memory store should read multiple keys" do
      store = ActiveSupport::Cache.lookup_store :memory_store
      store.write('a', 1)
      store.write('b', 2)

      expected = { 'a' => 1, 'b' => 2 }
      assert_equal expected, store.read_multi('a', 'b', 'c')
      assert_equal({}, store.read_multi)
    end
  end
end
