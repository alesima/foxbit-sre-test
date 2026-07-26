# ==============================================================================
# Stage 1: Builder (Compilação)
# ==============================================================================
FROM ruby:3.4-slim AS builder

WORKDIR /app

# Instala pacotes essenciais apenas para compilar gems no Stage 1
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

# Instala as gems dentro do diretório do projeto (vendor/bundle)
RUN bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf /root/.bundle/cache vendor/bundle/ruby/3.2.0/cache

# ==============================================================================
# Stage 2: Runtime (Imagem Final Limpa)
# ==============================================================================
FROM ruby:3.4-slim

WORKDIR /app

# Criar usuário não-root por segurança (UID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /bin/sh appuser

# Copia as gems já compiladas do Stage de Build
COPY --from=builder /app/vendor /app/vendor
COPY --from=builder /usr/local/bundle/config /usr/local/bundle/config

# Copia a aplicação atribuindo as permissões ao usuário sem privilégios
COPY --chown=appuser:appgroup . .

USER appuser

EXPOSE 8000

ENV RACK_ENV=production

CMD ["bundle", "exec", "puma", "-p", "8000", "-e", "production"]