# frozen_string_literal: true

require 'rack/attack'
require_relative 'config/rack_attack'
require_relative 'app'

use Rack::Attack
run CalcApi
