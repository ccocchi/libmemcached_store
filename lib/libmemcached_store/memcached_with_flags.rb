#
# Allow get method to returns value + entry's flags
# This is useful to set compression flag.
#

require 'memcached'

module LibmemcachedStore
  class MemcachedWithFlags < Memcached
    def get(keys, decode=true, with_flags=false)
      if keys.is_a? Array
        # inlined multi_get with changes to make it return flags and ignore cas
        ret = Lib.memcached_mget(@struct, keys)
        check_return_code(ret, keys)

        hash = {}
        flags_hash = {} if with_flags
        value, key, flags, ret = Lib.memcached_fetch_rvalue(@struct)
        while ret != 21 do # Lib::MEMCACHED_END
          if ret == 0 # Lib::MEMCACHED_SUCCESS
            flags_hash[key] = flags if with_flags
            hash[key] = decode ? [value, flags] : value
          elsif ret != 16 # Lib::MEMCACHED_NOTFOUND
            check_return_code(ret, key)
          end
          value, key, flags, ret = Lib.memcached_fetch_rvalue(@struct)
        end
        if decode
          hash.each do |key, value_and_flags|
            hash[key] = @codec.decode(key, *value_and_flags)
          end
        end

        # actual code we need
        with_flags ? [hash, flags_hash] : hash
      else
        result = single_get(keys, decode)
        with_flags ? result.first(2) : result.first
      end
    rescue => e
      tries ||= 0
      raise unless tries < options[:exception_retry_limit] && should_retry(e)
      tries += 1
      retry
    end
  end
end
