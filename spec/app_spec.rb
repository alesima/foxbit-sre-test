# spec/app_spec.rb
require_relative 'spec_helper'

RSpec.describe 'CalcApi' do
  it 'executa a adicao corretamente' do
    get '/api/sum?term_one=5&term_two=10'
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({ 'result' => 15 })
  end

  it 'executa a subtracao corretamente' do
    get '/api/sub?term_one=10&term_two=5'
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({ 'result' => 5 })
  end

  it 'executa a multiplicacao corretamente' do
    get '/api/mul?term_one=5&term_two=10'
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({ 'result' => 50 })
  end

  it 'executa a divisao corretamente' do
    get '/api/div?term_one=10&term_two=5'
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({ 'result' => 2 })
  end

  it 'retorna erro 400 ao tentar dividir por zero' do
    get '/api/div?term_one=10&term_two=0', {}, 'REMOTE_ADDR' => '127.0.0.10'
    expect(last_response.status).to eq(400)
  end

  it 'returna erro 400 se faltarem parametros' do
    get '/api/sum?term_one=10', {}, 'REMOTE_ADDR' => '127.0.0.11'
    expect(last_response.status).to eq(400)
  end

  describe 'Rate Limiting' do
    before do
      Rack::Attack.cache.store = Rack::Attack::MemoryStore.new
    end

    it 'permite requests dentro do limite' do
      5.times do |i|
        get "/api/sum?term_one=1&term_two=#{i}", {}, 'REMOTE_ADDR' => '1.2.3.4'
        expect(last_response.status).to eq(200)
      end
    end

    it 'bloqueia requests apos exceder o limite' do
      6.times do |i|
        get "/api/sum?term_one=1&term_two=#{i}", {}, 'REMOTE_ADDR' => '5.6.7.8'
        expect(last_response.status).to eq(429) if i >= 5
      end
    end

    it 'nao bloqueia healthcheck mesmo apos exceder limite' do
      10.times do
        get '/healthz/ready', {}, 'REMOTE_ADDR' => '9.9.9.9'
        expect(last_response.status).to eq(200)
      end
    end

    it 'bloqueia por IP independente' do
      6.times { get '/api/sum?term_one=1&term_two=2', {}, 'REMOTE_ADDR' => '10.0.0.1' }
      expect(last_response.status).to eq(429)

      get '/api/sum?term_one=1&term_two=2', {}, 'REMOTE_ADDR' => '10.0.0.2'
      expect(last_response.status).to eq(200)
    end
  end
end