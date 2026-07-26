# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

ENV['RACK_ENV'] = 'test'
ENV['RACK_ATTACK_LIMIT']  ||= '5'
ENV['RACK_ATTACK_PERIOD'] ||= '60'
ENV['RACK_ATTACK_BURST']  ||= '5'
ENV['RACK_ATTACK_BURST_PERIOD'] ||= '60'

require 'rack/attack'
require_relative '../config/rack_attack'
require_relative '../app'
require 'rack/test'

RSpec.configure do |config|
  config.include Rack::Test::Methods
  def app
    Rack::Builder.new do
      use Rack::Attack
      run CalcApi
    end
  end
end
