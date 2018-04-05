require 'memcached'
require 'libmemcached_store/memcached_with_flags'

require 'digest/md5'

module ActiveSupport
  module Cache

    #
    # Store using memcached gem as client
    #
    # Global options can be passed to be applied to each method by default.
    # Supported options are
    # * <tt>:compress</tt> : if set to true, data will be compress before stored
    # * <tt>:compress_threshold</tt> : specify the threshold at which to compress
    # value, default is 4K
    # * <tt>:namespace</tt> : prepend each key with this value for simple namespacing
    # * <tt>:expires_in</tt> : default TTL in seconds for each. Default value is 0, i.e. forever
    # Specific value can be passed per key with write and fetch command.
    #
    # Options can also be passed direclty to the memcache client, via the <tt>:client</tt>
    # option. For example, if you want to use pipelining, you can use
    # :client => { :no_block => true }
    #
    class LibmemcachedStore
      class FetchWithRaceConditionTTLEntry
        attr_accessor :value, :extended

        def initialize(value, expires_in)
          @value, @extended = value, false
          @expires_at = Time.now.to_i + expires_in
        end

        def expires_in
          [@expires_at - Time.now.to_i, 1].max # never set to 0 -> never expires
        end

        def expired?
          @expires_at <= Time.now.to_i
        end
      end

      attr_reader :addresses

      DEFAULT_CLIENT_OPTIONS = { distribution: :consistent_ketama, binary_protocol: true, default_ttl: 0 }
      ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/n
      DEFAULT_COMPRESS_THRESHOLD = 4096
      FLAG_COMPRESSED = 0x2

      attr_reader :silence, :options
      alias_method :silence?, :silence

      # Silence the logger.
      def silence!
        @silence = true
        self
      end

      # Silence the logger within a block.
      def mute
        previous_silence, @silence = defined?(@silence) && @silence, true
        yield
      ensure
        @silence = previous_silence
      end

      def initialize(*addresses)
        addresses.flatten!
        options = addresses.extract_options!
        client_options = options.delete(:client) || {}
        if options[:namespace]
          client_options[:prefix_key] = options.delete(:namespace)
          client_options[:prefix_delimiter] = ':'
        end
        @namespace_length = "#{client_options[:prefix_key]}#{client_options[:prefix_delimiter]}".force_encoding("BINARY").size

        client_options[:default_ttl] = options.delete(:expires_in).to_i if options[:expires_in]

        @options = {compress_threshold: DEFAULT_COMPRESS_THRESHOLD}.merge(options)
        @addresses = addresses
        @cache = ::LibmemcachedStore::MemcachedWithFlags.new(@addresses, DEFAULT_CLIENT_OPTIONS.merge(client_options))
      end

      def fetch(key, options = nil, &block)
        if block_given?
          if options && options[:race_condition_ttl] && options[:expires_in]
            fetch_with_race_condition_ttl(key, options, &block)
          else
            key = normalize_key(key)
            unless options && options[:force]
              entry = instrument(:read, key, options) do |payload|
                read_entry(key, options).tap do |result|
                  if payload
                    payload[:super_operation] = :fetch
                    payload[:hit] = !!result
                  end
                end
              end
            end

            if entry.nil?
              result = instrument(:generate, key, options) do |payload|
                yield
              end
              write_entry(key, result, options)
              result
            else
              instrument(:fetch_hit, key, options) { |payload| }
              entry
            end
          end
        else
          read(key, options)
        end
      end

      def read(key, options = nil)
        key = normalize_key(key)
        instrument(:read, key, options) do |payload|
          entry = read_entry(key, options)
          payload[:hit] = !!entry if payload
          entry
        end
      end

      def write(key, value, options = nil)
        key = normalize_key(key)
        instrument(:write, key, options) do |payload|
          write_entry(key, value, options)
        end
      end

      def delete(key, options = nil)
        key = normalize_key(key)
        instrument(:delete, key) do |payload|
          delete_entry(key, options)
        end
      end

      def exist?(key, options = nil)
        key = normalize_key(key)
        instrument(:exist?, key) do |payload|
          if @cache.respond_to?(:exist)
            @cache.exist(key)
            true
          else
            read_entry(key, options) != nil
          end
        end
      rescue Memcached::NotFound
        false
      end

      def increment(key, amount = 1, options = nil)
        key = normalize_key(key)
        instrument(:increment, key, amount: amount) do
          @cache.incr(key, amount)
        end
      rescue Memcached::NotFound
        nil
      rescue Memcached::Error => e
        log_error(e)
        nil
      end

      def decrement(key, amount = 1, options = nil)
        key = normalize_key(key)
        instrument(:decrement, key, amount: amount) do
          @cache.decr(key, amount)
        end
      rescue Memcached::NotFound
        nil
      rescue Memcached::Error => e
        log_error(e)
        nil
      end

      def read_multi(*names)
        names.flatten!
        options = names.extract_options!

        return {} if names.empty?

        mapping = Hash[names.map {|name| [normalize_key(name), name] }]
        keys = mapping.keys
        raw_values, flags = instrument(:read_multi, keys, options) do
          @cache.get(keys, false, true)
        end

        values = {}
        raw_values.each do |key, value|
          values[mapping[key]] = convert_race_condition_entry(deserialize(value, options[:raw], flags[key]))
        end
        values
      rescue Memcached::Error => e
        log_error(e)
        {}
      end

      def clear(options = nil)
        instrument(:clear, "*") do
          @cache.flush
        end
      end

      def stats
        @cache.stats
      end

      protected

      def read_entry(key, options = nil)
        options ||= {}
        raw_value, flags = @cache.get(key, false, true)
        value = deserialize(raw_value, options[:raw], flags)
        convert_race_condition_entry(value, options)
      rescue Memcached::NotFound
        nil
      rescue Memcached::Error => e
        log_error(e)
        nil
      end

      def write_entry(key, entry, options = nil)
        options = options ? @options.merge(options) : @options
        method = options[:unless_exist] ? :add : :set
        entry = options[:raw] ? entry.to_s : Marshal.dump(entry)
        flags = 0

        if options[:compress] && entry.bytesize >= options[:compress_threshold]
          entry = Zlib::Deflate.deflate(entry)
          flags |= FLAG_COMPRESSED
        end

        @cache.send(method, key, entry, options[:expires_in].to_i, false, flags)
        true
      rescue Memcached::Error => e
        log_error(e)
        false
      end

      def delete_entry(key, options = nil)
        @cache.delete(key)
        true
      rescue Memcached::NotFound
        false
      rescue Memcached::Error => e
        log_error(e)
        false
      end

      private

      def fetch_with_race_condition_ttl(key, options={}, &block)
        options = options.dup

        race_ttl = options.delete(:race_condition_ttl) || raise("Use :race_condition_ttl option or normal fetch")
        expires_in = options.fetch(:expires_in)
        options[:expires_in] = expires_in + race_ttl
        options[:preserve_race_condition_entry] = true

        value = fetch(key, options) { FetchWithRaceConditionTTLEntry.new(yield, expires_in) }

        return value unless value.is_a?(FetchWithRaceConditionTTLEntry)

        if value.expired? && !value.extended
          # we take care of refreshing the cache, all others should keep reading
          value.extended = true
          write(key, value, options.merge(:expires_in => value.expires_in + race_ttl))

          # calculate new value and store it
          value = FetchWithRaceConditionTTLEntry.new(yield, expires_in)
          write(key, value, options)
        end

        value.value
      end

      def convert_race_condition_entry(value, options={})
        if !options[:preserve_race_condition_entry] && value.is_a?(FetchWithRaceConditionTTLEntry)
          value.value
        else
          value
        end
      end

      def deserialize(value, raw = false, flags = 0)
        value = Zlib::Inflate.inflate(value) if (flags & FLAG_COMPRESSED) != 0
        raw ? value : Marshal.load(value)
      rescue TypeError, ArgumentError
        value
      end

      # TODO: support namespace or other things passed as option
      def normalize_key(key, _options = nil)
        escape_and_normalize(expanded_key(key))
      end

      def escape_and_normalize(key)
        key = key.to_s.dup.force_encoding("BINARY").gsub(ESCAPE_KEY_CHARS) { |match| "%#{match.getbyte(0).to_s(16).upcase}" }
        key_length = key.length

        return key if @namespace_length + key_length <= 250

        max_key_length = 213 - @namespace_length
        "#{key[0, max_key_length]}:md5:#{Digest::MD5.hexdigest(key)}"
      end

      def expanded_key(key) # :nodoc:
        return key.cache_key.to_s if key.respond_to?(:cache_key)

        case key
        when Array
          if key.size > 1
            key = key.collect { |element| expanded_key(element) }
          else
            key = key.first
          end
        when Hash
          key = key.sort_by { |k,_| k.to_s }.collect { |k, v| "#{k}=#{v}" }
        end

        key.to_param
      end

      def instrument(operation, key, options=nil)
        log(operation, key, options)

        if instrument?
          payload = { :key => key }
          payload.merge!(options) if options.is_a?(Hash)
          ActiveSupport::Notifications.instrument("cache_#{operation}.active_support", payload){ yield(payload) }
        else
          yield(nil)
        end
      end

      def instrument?
        ActiveSupport::VERSION::MAJOR == 3 ? ActiveSupport::Cache::Store.instrument : true
      end

      def log(operation, key, options=nil)
        return unless !silence? && logger && logger.debug?
        logger.debug("Cache #{operation}: #{key}#{options.blank? ? "" : " (#{options.inspect})"}")
      end

      def log_error(exception)
        return unless !silence? && logger && logger.error?
        logger.error "MemcachedError (#{exception.inspect}): #{exception.message}"
      end

      def logger
        Rails.logger
      end
    end
  end
end
