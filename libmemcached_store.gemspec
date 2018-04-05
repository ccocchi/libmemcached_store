require "./lib/libmemcached_store/version"

Gem::Specification.new do |s|
  s.name        = "libmemcached_store"
  s.version     = LibmemcachedStore::VERSION
  s.summary     = "ActiveSupport 3+ cache store for the C-based libmemcached client"
  s.email       = "cocchi.c@gmail.com"
  s.homepage    = "https://github.com/ccocchi/libmemcached_store"
  s.description = %q{An ActiveSupport cache store that uses the C-based libmemcached client through
      Evan Weaver's Ruby/SWIG wrapper, memcached. libmemcached is fast, lightweight,
      and supports consistent hashing, non-blocking IO, and graceful server failover.}
  s.authors     = ["Christopher Cocchi-Perrier", "Ben Hutton", "Jeffrey Hardy"]
  s.license     = "MIT"
  s.files       = `git ls-files lib`.split("\n")

  s.required_ruby_version = '>= 2.2.0'

  s.add_dependency('memcached', '~> 1.8.0') # re-check lib/memcached/memcached_with_flags_test.rb before bumping

  s.add_development_dependency('rack')
  s.add_development_dependency('rake')
  s.add_development_dependency('bump')
  s.add_development_dependency('mocha')
  s.add_development_dependency('dalli')
  s.add_development_dependency('minitest')
  s.add_development_dependency('minitest-rg')
  s.add_development_dependency('activesupport', '>= 3', '< 5')
  s.add_development_dependency('actionpack', '>= 3', '< 5')
  s.add_development_dependency('single_cov')
end

