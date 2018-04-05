require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest

require 'minitest/autorun'
require 'minitest/rg'
require 'mocha/setup'

ENV["RAILS_ENV"] = "test"
