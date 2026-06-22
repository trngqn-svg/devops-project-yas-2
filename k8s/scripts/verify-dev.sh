#!/usr/bin/env bash
set -euo pipefail

kubectl get nodes -o wide
kubectl get namespaces
helm list -A
kubectl get pods,svc -n yas-infra
kubectl get pods,svc -n dev

echo
echo "Testing service health from inside namespace dev..."
kubectl run yas-health-check \
  --namespace dev \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  --rm -i \
  --command -- sh -c \
  'curl -fsS http://product/actuator/health/readiness && echo &&
   curl -fsS http://media/actuator/health/readiness && echo &&
   curl -fsS http://location/actuator/health/readiness && echo'

