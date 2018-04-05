# LibmemcachedStore

An ActiveSupport cache store that uses the fast, C-based, libmemcached client [memcached](https://github.com/evan/memcached).
It is the fastest ruby memcached client, lightweight, supports consistent hashing, non-blocking IO, and graceful server failover.

## Installation

```ruby
# Gemfile
gem 'libmemcached_store'
```

## Usage

This is a drop-in replacement for the memcache store that ships with Rails.

```ruby
# config/environments/*.rb
config.cache_store = :libmemcached_store
```

If no servers are specified, localhost is assumed. You can specify a list of
server addresses, either as hostnames or IP addresses, with or without a port
designation. If no port is given, 11211 is assumed:

```ruby
config.cache_store = :libmemcached_store, %w(cache-01 cache-02 127.0.0.1:11212)
```

Standard Rails cache store options can be used

```ruby
config.cache_store = :libmemcached_store, '127.0.0.1:11211', {compress: true, expires_in: 3600}
```

More advanced options can be passed directly to the client

```ruby
config.cache_store = :libmemcached_store, '127.0.0.1:11211', {client: { binary_protocol: true, no_block: true }}
```

You can also use `:libmemcached_store` to store your application sessions

```ruby
require 'action_dispatch/session/libmemcached_store'
config.session_store :libmemcached_store, namespace: '_session', expire_after: 1800
```

You can use `:libmemcached_local_store` if you want a local in-memory cache for each request

```ruby
config.cache_store :libmemcached_local_store
```


Increment / Decrement only work on raw values:

```ruby
Rails.cache.write 'x', '1', raw: true
Rails.cache.increment 'x' # => 2
Rails.cache.decrement 'x' # => 1
```

## Performance

Used with Rails, __libmemcached_store__ is at least 1.5x faster than __dalli__. See [BENCHMARKS](https://github.com/ccocchi/libmemcached_store/blob/master/BENCHMARKS)
for details

## Props

Thanks to Brian Aker ([http://tangent.org](http://tangent.org)) for creating libmemcached, and Evan
Weaver ([http://blog.evanweaver.com](http://blog.evanweaver.com)) for the Ruby wrapper.
