# frozen_string_literal: true

module Rack
  class Attack
    class MemoryStore
      def initialize
        @data = {}
      end
      def read(key)
        @data[key]
      end
      def write(key, value, _options = {})
        @data[key] = value
      end
      def increment(key, count = 1, _options = {})
        @data[key] = (@data[key] || 0) + count
      end
      def delete(key)
        @data.delete(key)
      end
      def reset!
        @data.clear
      end
    end
  end
end

LIMIT  = ENV.fetch('RACK_ATTACK_LIMIT', 10_000).to_i
PERIOD = ENV.fetch('RACK_ATTACK_PERIOD', 60).to_i

BURST_LIMIT  = ENV.fetch('RACK_ATTACK_BURST', 200).to_i
BURST_PERIOD = ENV.fetch('RACK_ATTACK_BURST_PERIOD', 1).to_i

Rack::Attack.cache.store = Rack::Attack::MemoryStore.new

# Healthz e metrics nunca sao rate-limited
Rack::Attack.safelist('allow healthz and metrics') do |req|
  req.path.start_with?('/healthz', '/metrics')
end

# API endpoints: burst limit (ex: 200 req/s)
Rack::Attack.throttle('api/burst', limit: BURST_LIMIT, period: BURST_PERIOD) do |req|
  req.ip if req.path.start_with?('/api')
end

# API endpoints: janela longa (ex: 10k req/min)
Rack::Attack.throttle('api/ip', limit: LIMIT, period: PERIOD) do |req|
  req.ip if req.path.start_with?('/api')
end

# Resposta 429
Rack::Attack.throttled_responder = lambda do |_env|
  [429, { 'Content-Type' => 'application/json' },
   [{ error: 'Rate limit exceeded. Try again later.' }.to_json]]
end
