require 'bundler/gem_tasks'
require 'rake/testtask'

desc 'Test the libmemcached_store plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

task :default => :test
