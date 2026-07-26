# frozen_string_literal: true

# app.rb
require 'sinatra/base'
require 'json'
require 'prometheus/client'
require 'prometheus/client/formats/text'

class CalcApi < Sinatra::Base
  configure do
    set :bind, '0.0.0.0'
    set :port, 8000
    set :show_exceptions, false
  end

  # Configuracao de metricas do prometheus
  prometheus = Prometheus::Client.registry
  HTTP_REQUESTS = Prometheus::Client::Counter.new(
    :http_requests_total,
    docstring: 'Total HTTP Requests',
    labels: %i[endpoint status]
  )

  prometheus.register(HTTP_REQUESTS) unless prometheus.exist?(:http_requests_total)

  before do
    content_type :json
  end

  after do
    if response.status < 400 && request.path_info.start_with?('/api')
      HTTP_REQUESTS.increment(labels: { endpoint: request.path_info, status: response.status })
    end
  end

  # Healthchecks (Probes do K8s)
  get '/healthz/live' do
    status 200
    { status: 'ALIVE' }.to_json
  end

  get '/healthz/ready' do
    status 200
    { status: 'READY' }.to_json
  end

  # Endpoint de metricas
  get '/metrics' do
    content_type 'text/plain'
    Prometheus::Client::Formats::Text.marshal(Prometheus::Client.registry)
  end

  # Endpoints da API
  get '/api/sum' do
    calculate { |a, b| a + b }
  end

  get '/api/sub' do
    calculate { |a, b| a - b }
  end

  get '/api/mul' do
    calculate { |a, b| a * b }
  end

  get '/api/div' do
    t1, t2 = parse_terms
    return render_error(400, 'term_two cannot be zero') if t2.zero?

    calculate { t1 / t2 }
  rescue ArgumentError => e
    render_error(400, e.message)
  end

  private

  def parse_terms
    p1 = params['term_one']
    p2 = params['term_two']
    validate_terms!(p1, p2)
    [p1.to_i, p2.to_i]
  end

  def validate_terms!(param_one, param_two)
    if param_one.nil? || param_two.nil? || param_one.strip.empty? || param_two.strip.empty?
      raise ArgumentError, 'Missing required parameters: term_one and term_two'
    end

    return if param_one.match?(/\A-?\d+\z/) && param_two.match?(/\A-?\d+\z/)

    raise ArgumentError, 'Parameters must be integers'
  end

  def calculate
    t1, t2 = parse_terms
    res = yield(t1, t2)
    { result: res }.to_json
  rescue ArgumentError => e
    render_error(400, e.message)
  end

  def render_error(status_code, message)
    status status_code
    { error: message }.to_json
  end
end
