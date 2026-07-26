# ==============================================================================
# Foxbit SRE Challenge - Makefile
# ==============================================================================

.PHONY: help setup test lint build cluster cluster-destroy deploy destroy validate eval

# Variáveis configuráveis (substituíveis via linha de comando)
IMAGE_NAME   ?= calc-api
IMAGE_TAG    ?= v1.0.0
CLUSTER_NAME ?= foxbit-sre-cluster
NAMESPACE    ?= calc-api-test
DEPLOY_TYPE  ?= helm # Opções: 'helm' ou 'k8s'

# Caminhos internos
HELM_RELEASE ?= calc-api
HELM_CHART   ?= ./charts/calc-api
K8S_PATH     ?= ./k8s

help: ## Exibe este menu de ajuda
	@echo "Uso: make [target] [NAMESPACE=nome] [DEPLOY_TYPE=helm|k8s]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Instala dependências Ruby locais
	bundle install

test: ## Executa testes unitários com RSpec
	bundle exec rspec

lint: ## Executa linter Rubocop e Hadolint no Dockerfile
	bundle exec rubocop
	hadolint Dockerfile

build: ## Executa o build da imagem Docker
	@echo "==> Building da imagem Docker: $(IMAGE_NAME):$(IMAGE_TAG)"
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

cluster: ## Cria um cluster Kubernetes local usando KinD
	@echo "==> Criando cluster KinD: $(CLUSTER_NAME)"
	kind create cluster --name $(CLUSTER_NAME) --wait 60s

cluster-destroy: ## Remove o cluster Kubernetes local do KinD
	@echo "==> Destruindo cluster KinD: $(CLUSTER_NAME)"
	kind delete cluster --name $(CLUSTER_NAME)

deploy: ## Aplica a aplicação no cluster (DEPLOY_TYPE=helm ou DEPLOY_TYPE=k8s)
	@if [ "$(DEPLOY_TYPE)" = "helm" ]; then \
		echo "==> [HELM] Fazendo deploy na release '$(HELM_RELEASE)' no namespace '$(NAMESPACE)'..."; \
		kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(CLUSTER_NAME) 2>&1 || true; \
		helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
			--namespace $(NAMESPACE) \
			--create-namespace \
			--set image.repository=$(IMAGE_NAME) \
			--set image.tag=$(IMAGE_TAG) \
			--wait; \
	elif [ "$(DEPLOY_TYPE)" = "k8s" ]; then \
		echo "==> [K8S/KUSTOMIZE] Fazendo deploy no namespace '$(NAMESPACE)'..."; \
		kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -; \
		kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(CLUSTER_NAME) 2>&1 || true; \
		kubectl apply -k $(K8S_PATH) -n $(NAMESPACE); \
		kubectl set image deployment/calc-api calc-api=$(IMAGE_NAME):$(IMAGE_TAG) -n $(NAMESPACE) || true; \
		kubectl rollout status deployment/calc-api -n $(NAMESPACE) --timeout=90s; \
	else \
		echo "Erro: DEPLOY_TYPE inválido. Use 'helm' ou 'k8s'."; exit 1; \
	fi

destroy: ## Remove a aplicação e o namespace do cluster
	@if [ "$(DEPLOY_TYPE)" = "helm" ]; then \
		echo "==> [HELM] Removendo release do namespace '$(NAMESPACE)'..."; \
		helm uninstall $(HELM_RELEASE) -n $(NAMESPACE) || true; \
	elif [ "$(DEPLOY_TYPE)" = "k8s" ]; then \
		echo "==> [K8S/KUSTOMIZE] Removendo recursos do namespace '$(NAMESPACE)'..."; \
		kubectl delete -k $(K8S_PATH) -n $(NAMESPACE) --ignore-not-found=true; \
	fi
	@kubectl delete namespace $(NAMESPACE) --ignore-not-found=true

validate: ## Testa a API com requisições HTTP internas no namespace ativo
	@echo "==> Validando comunicação interna no namespace '$(NAMESPACE)'..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app=calc-api -o jsonpath='{.items[0].metadata.name}'); \
	SCRIPT='require "net/http"; \
	  def t(d,p); u=URI("http://localhost:8000#{p}"); r=Net::HTTP.get_response(u); puts "#{d}: [#{r.code}] #{r.body}"; rescue => e; puts "#{d}: ERROR - #{e}"; end; \
	  puts "=== Happy Path ==="; \
	  t("1. Adição (4+2)", "/api/sum?term_one=4&term_two=2"); \
	  t("2. Subtração (4-1)", "/api/sub?term_one=4&term_two=1"); \
	  t("3. Multiplicação (3*5)", "/api/mul?term_one=3&term_two=5"); \
	  t("4. Divisão (10/2)", "/api/div?term_one=10&term_two=2"); \
	  t("5. Healthcheck", "/healthz/ready"); \
	  puts ""; \
	  puts "=== Error Cases ==="; \
	  t("6. Divisão por zero",   "/api/div?term_one=10&term_two=0"); \
	  t("7. Params ausentes",    "/api/sum"); \
	  t("8. Parâmetro inválido", "/api/sum?term_one=abc&term_two=2"); \
	  t("9. Parâmetro faltando", "/api/sub?term_one=5")'; \
	printf '%s' "$$SCRIPT" | kubectl exec -i -n $(NAMESPACE) $$POD -- ruby

load-test: ## Executa teste de carga com k6 (port-forward + docker)
	@echo "==> Executando k6 load test no namespace '$(NAMESPACE)'..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app=calc-api -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(NAMESPACE) $$POD 8001:8000 & \
	PF_PID=$$!; \
	sleep 3; \
	docker run --rm -i --network host -e BASE_URL=http://localhost:8001 grafana/k6:latest run - < test/k6/load_test.js; \
	kill $$PF_PID 2>/dev/null; \
	wait

rate-limit-test: ## Testa o rate limit com k6 (envia 100 requisicoes e verifica 429)
	@echo "==> Executando k6 rate-limit test no namespace '$(NAMESPACE)'..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app=calc-api -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(NAMESPACE) $$POD 8001:8000 & \
	PF_PID=$$!; \
	sleep 3; \
	docker run --rm -i --network host -e BASE_URL=http://localhost:8001 grafana/k6:latest run - < test/k6/rate_limit_test.js; \
	kill $$PF_PID 2>/dev/null; \
	wait

eval: ## Avaliação automatizada completa (Aceita NAMESPACE e DEPLOY_TYPE)
	@echo "======================================================================"
	@echo " Running Evaluation (Engine: $(DEPLOY_TYPE) | Namespace: $(NAMESPACE))"
	@echo "======================================================================"
	@make cluster
	@make build
	@echo "==> Carregando imagem no KinD..."
	kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(CLUSTER_NAME)
	@make deploy NAMESPACE=$(NAMESPACE) DEPLOY_TYPE=$(DEPLOY_TYPE)
	@make validate NAMESPACE=$(NAMESPACE)
	@echo "======================================================================"
	@echo " Avaliação concluída com sucesso!"
	@echo "======================================================================"