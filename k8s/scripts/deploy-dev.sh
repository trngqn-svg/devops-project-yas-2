#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for namespace in yas-infra dev staging argocd istio-system; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done

bash "$ROOT_DIR/k8s/scripts/build-helm-dependencies.sh"

helm lint "$ROOT_DIR/k8s/charts/yas-infra"
helm lint "$ROOT_DIR/k8s/charts/yas-platform" \
  -f "$ROOT_DIR/k8s/charts/yas-platform/values-dev.yaml"

helm upgrade --install yas-infra "$ROOT_DIR/k8s/charts/yas-infra" \
  --namespace yas-infra \
  --wait \
  --timeout 10m

kubectl rollout status deployment/postgresql -n yas-infra --timeout=5m
kubectl rollout status deployment/redis -n yas-infra --timeout=5m
kubectl rollout status deployment/identity -n yas-infra --timeout=10m

helm upgrade --install yas-dev "$ROOT_DIR/k8s/charts/yas-platform" \
  --namespace dev \
  -f "$ROOT_DIR/k8s/charts/yas-platform/values-dev.yaml" \
  --wait \
  --timeout 20m

kubectl get pods,svc -n yas-infra
kubectl get pods,svc -n dev
