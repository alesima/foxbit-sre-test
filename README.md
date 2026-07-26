# 🚀 Foxbit SRE Challenge - Calculator API

[![CI/CD Pipeline](https://img.shields.io/badge/CI%2FCD%20with-GitHub_Actions-2088FF?logo=githubactions&logoColor=2088FF&link=https%3A%2F%github.com%2Ffeatures%2Factions.svg)](https://github.com/foxbit-sre-challenge/calc-api/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/Ruby-3.4-red.svg)](https://www.ruby-lang.org/)
[![Framework](https://img.shields.io/badge/Framework-Sinatra%20%2F%20Puma-blue.svg)](https://sinatrarb.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Compatible-blue.svg)](https://kubernetes.io/)
[![SAST](https://img.shields.io/badge/SAST-Brakeman%20%7C%20Hadolint-brightgreen.svg)]()
[![DAST](https://img.shields.io/badge/DAST-OWASP%20ZAP-orange.svg)]()

API RESTful de nível de produção e alta disponibilidade construída em **Ruby (Sinatra)** para operações matemáticas básicas, projetada especificamente para deployments em Kubernetes seguindo as melhores práticas de SRE.

---

## 📌 Sumário
- [Arquitetura & Stack Tecnológica](#-arquitetura--stack-tecnológica)
- [Pré-requisitos](#-pré-requisitos)
- [Início Rápido para Avaliadores](#-início-rápido-para-avaliadores)
- [Documentação da API](#-documentação-da-api)
- [Deploy & Testes no Kubernetes](#-deploy--testes-no-kubernetes)
- [Observabilidade & Health Checks](#-observabilidade--health-checks)
- [DevSecOps (SAST & DAST)](#-devsecops-sast--dast)
- [Limpeza](#-limpeza)

---

## 🏗 Arquitetura & Stack Tecnológica

- **Linguagem & Framework:** Ruby 3.4 + Sinatra (Framework de API leve) rodando no servidor de aplicação Puma.
- **Containerização:** Build Docker multi-estágio compatível com OCI, usuário não-root (`appuser:10001`), execução sem root.
- **Arquitetura Kubernetes:**
  - `Deployment`: Alta disponibilidade (2 réplicas), atualizações rolling sem downtime, limites/requests de recursos configurados.
  - `Service`: `ClusterIP` (Acesso estritamente interno — não exposto à internet pública).
  - `NetworkPolicy`: Isolamento de ingresso limitando o tráfego exclusivamente a workloads dentro do mesmo namespace.
  - `HPA`: Escalonamento automático baseado em CPU/Memória (2 a 5 pods).
- **Observabilidade:** Métricas nativas do Prometheus (`/metrics`) e probes de Liveness/Readiness do Kubernetes (`/healthz/*`).

---

## 🛑 Pré-requisitos

Certifique-se de ter as seguintes ferramentas CLI instaladas localmente:
- `docker` (v20.10+)
- `kubectl` (v1.24+)
- `kind` ou `minikube` (para execução em cluster local)
- `make`

---

## ⚡ Início Rápido para Avaliadores

Você pode executar todo o ciclo de vida (criação do cluster, build, deploy e validação) com um único comando:

```bash
make eval
```

Isso automatiza:
1. Criação do cluster Kubernetes local (`kind`).
2. Build da imagem Docker multi-estágio.
3. Carregamento da imagem no cluster local.
4. Aplicação dos manifests K8s (`Deployment`, `Service`, `NetworkPolicy`, `HPA`).
5. Execução de testes automatizados de validação com `curl` contra todos os 4 endpoints matemáticos.

---

## 📖 Documentação da API

Todos os endpoints matemáticos esperam `term_one` e `term_two` como parâmetros de consulta (query params) do tipo inteiro e retornam um payload JSON: `{"result": <int>}`.

| Operação | Método | Endpoint | Exemplo | Resposta |
| :--- | :--- | :--- | :--- | :--- |
| **Adição** | `GET` | `/api/sum` | `/api/sum?term_one=4&term_two=2` | `{"result": 6}` |
| **Subtração** | `GET` | `/api/sub` | `/api/sub?term_one=4&term_two=1` | `{"result": 3}` |
| **Multiplicação** | `GET` | `/api/mul` | `/api/mul?term_one=3&term_two=5` | `{"result": 15}` |
| **Divisão** | `GET` | `/api/div` | `/api/div?term_one=10&term_two=2` | `{"result": 5}` |

### Tratamento de Erros
- **Parâmetros Ausentes / Inválidos:** Retorna `400 Bad Request` (`{"error": "Parameters must be integers"}`).
- **Divisão por Zero:** Retorna `400 Bad Request` (`{"error": "term_two cannot be zero"}`).

---

## ☸️ Deploy & Testes no Kubernetes

### 1. Deploy Manual em um Cluster K8s Existente
Se preferir fazer o deploy no seu próprio cluster Kubernetes:

```bash
# Build e tag da imagem
docker build -t calc-api:v1.0.0 .

# Aplicar manifests K8s
kubectl apply -f k8s/
```

### 2. Validando Acesso Interno (Verificação de Requisito)
Conforme os requisitos, a aplicação é **acessível apenas dentro do cluster** (via serviço `ClusterIP`).

Para testar endpoints manualmente de dentro do cluster, inicie um pod temporário de teste:

```bash
kubectl run curl-test --image=curlimages/curl:latest -i --tty --rm --   curl -s "http://calc-api-service.default.svc.cluster.local/api/sub?term_one=4&term_two=1"
```

*Saída Esperada:*
```json
{"result": 3}
```

### 3. Simulando uma Atualização da Aplicação (Zero Downtime)
Para testar a atualização da aplicação e aplicar um novo deployment:

```bash
# Build da versão atualizada
docker build -t calc-api:v1.0.1 .

# Atualizar a imagem do deployment
kubectl set image deployment/calc-api calc-api=calc-api:v1.0.1

# Acompanhar o rollout
kubectl rollout status deployment/calc-api
```

---

## 📊 Observabilidade & Health Checks

- **Liveness Probe:** `GET /healthz/live` (Retorna HTTP 200 `{"status":"ALIVE"}`)
- **Readiness Probe:** `GET /healthz/ready` (Retorna HTTP 200 `{"status":"READY"}`)
- **Métricas Prometheus:** `GET /metrics` (Expõe contadores de requisições HTTP e latências)

Para inspecionar métricas localmente via port-forwarding:

```bash
kubectl port-forward svc/calc-api-service 8000:8000
curl http://localhost:8000/metrics
```

---

## 🛡️ DevSecOps (SAST & DAST)

Este projeto adota uma postura de **Shift-Left Security** integrada ao GitHub Actions:

1. **SAST (Teste Estático de Segurança da Aplicação):**
   - **Brakeman:** Scanner de vulnerabilidades Ruby.
   - **Bundler-Audit:** Verificação de CVEs conhecidas nas dependências Gem.
   - **Hadolint:** Linting do Dockerfile e boas práticas de segurança.
2. **DAST (Teste Dinâmico de Segurança da Aplicação):**
   - **OWASP ZAP Baseline Scan:** Varredura automatizada de vulnerabilidades em runtime contra endpoints containerizados em execução na CI.

---

## ⚙️ Configuração do GitHub Actions

Para executar os pipelines de [CI](.github/workflows/ci.yml) e [CD](.github/workflows/cd.yml), configure as variáveis em **Settings → Secrets and variables → Actions** do repositório:

### Variáveis (Variables)

| Nome | Descrição | Padrão | Obrigatório |
|---|---|---|---|
| `AWS_REGION` | Região AWS para ECR e EKS | `us-east-1` | Apenas CD |
| `ECR_REPOSITORY` | Nome do repositório ECR | `calc-api` | Apenas CD |
| `EKS_CLUSTER_NAME` | Nome do cluster EKS | — | CD |
| `NAMESPACE` | Namespace K8s para deploy | `calc-api-system` | Não |

### Segredos (Secrets)

| Nome | Descrição | Obrigatório |
|---|---|---|
| `ROLE_TO_ASSUME` | ARN da IAM Role para OIDC (ex: `arn:aws:iam::123456789012:role/GitHubActionsEKSDeployer`) | CD (opcional no CI) |

> **Nota:** O CI possui valores padrão para `AWS_REGION` e `ECR_REPOSITORY`. O CD exige que todas as variáveis estejam configuradas (exceto `NAMESPACE`, que tem fallback).

---

## 🧹 Limpeza

Para remover todos os recursos implantados do seu cluster:

```bash
make destroy
```

Se você criou um cluster `kind` local via `make eval` ou `make cluster`, destrua todo o ambiente com:

```bash
make cluster-destroy
```
