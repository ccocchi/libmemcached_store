require_relative '../test_helper'
require 'libmemcached_store/memcached_with_flags'

SingleCov.covered! uncovered: 2 # TODO: figure out how to get `ret != 16`

describe LibmemcachedStore::MemcachedWithFlags do
  let(:options) { {} }
  let(:cache) { LibmemcachedStore::MemcachedWithFlags.new(['127.0.0.1'], options) }

  before do
    cache.set 'a', 1
    cache.set 'b', 2
  end

  describe "#get" do
    it "can get simple values" do
      cache.get('a').must_equal 1
    end

    it "can get multiple" do
      cache.get(['a', 'b']).must_equal "a" => 1, "b" => 2
    end

    it "ignores unfound multiple" do
      cache.get(['a', 'c']).must_equal "a" => 1
    end

    it "raises notfound" do
      assert_raises(Memcached::NotFound) { cache.get('c') }
    end

    describe "flags" do
      it "returns flags" do
        cache.get('a', true, true).must_equal [1, 0]
      end

      it "returns flags for multiple keys" do
        cache.get(['a', 'b'], true, true).must_equal [{"a" => 1, "b" => 2}, {"a" => 0, "b" => 0}]
      end
    end

    describe "raw" do
      it "does not de-marshal" do
        cache.get('a', false).must_equal "\x04\bi\x06"
      end

      it "does not de-marshal multiple keys" do
        cache.get(['a', 'b'], false).must_equal "a" => "\x04\bi\x06", "b" => "\x04\bi\a"
      end
    end

    describe "with retries" do
      let(:options) { {exception_retry_limit: 2} }

      it "retries and fails" do
        cache.expects(:check_return_code).raises(Memcached::ServerIsMarkedDead).times(3)
        assert_raises(Memcached::ServerIsMarkedDead) { cache.get('a') }
      end

      it "retries and succeeds" do
        cache.expects(:check_return_code).returns(nil)
        cache.expects(:check_return_code).raises(Memcached::ServerIsMarkedDead)
        cache.get('a')
      end
    end
  end
end
