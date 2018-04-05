#
# Allow get method to returns value + entry's flags
# This is useful to set compression flag.
#

require 'memcached'

module LibmemcachedStore
  class MemcachedWithFlags < Memcached
    def get(keys, marshal=true, with_flags=false)
      if keys.is_a? Array
        # Multi get
        ret = Memcached::Lib.memcached_mget(@struct, keys);
        check_return_code(ret, keys)

        hash, flags_hash = {}, {}
        value, key, flags, ret = Memcached::Lib.memcached_fetch_rvalue(@struct)
        while ret != 21 do # Lib::MEMCACHED_END
          if ret == 0 # Lib::MEMCACHED_SUCCESS
            hash[key] = value
            flags_hash[key] = flags if with_flags
          elsif ret != 16 # Lib::MEMCACHED_NOTFOUND
            check_return_code(ret, key)
          end
          value, key, flags, ret = Memcached::Lib.memcached_fetch_rvalue(@struct)
        end
        if marshal
          hash.each do |key, value|
            hash[key] = Marshal.load(value)
          end
        end
        with_flags ? [hash, flags_hash] : hash
      else
        # Single get
        value, flags, ret = Memcached::Lib.memcached_get_rvalue(@struct, keys)
        check_return_code(ret, keys)
        value =  Marshal.load(value) if marshal
        with_flags ? [value, flags] : value
      end
    rescue => e
      tries ||= 0
      raise unless tries < options[:exception_retry_limit] && should_retry(e)
      tries += 1
      retry
    end
  end
end
