# YAS Kubernetes deployment (GCP kubeadm)

This document deploys the assignment-sized YAS environment to one Kubernetes
control-plane VM and one worker VM. It intentionally excludes observability,
Kafka, Elasticsearch and recommendation to fit a 16 GiB worker.

## 1. Prerequisites

- `yas-master` and `yas-worker` are both `Ready`.
- Calico or another CNI is running.
- `kubectl`, Git and Helm 3 are installed on `yas-master`.
- GCP firewall allows TCP `30080-30090` from team member IP addresses.

Verify:

```bash
kubectl get nodes -o wide
kubectl get pods -A
helm version
git --version
```

## 2. Clone the team repository

Clone the team fork, not the original upstream repository, because the team
fork contains `yas-infra`, `yas-platform` and the deployment scripts.

```bash
cd ~
git clone https://github.com/<TEAM_OR_USER>/yas.git
cd yas
git checkout <K8S_BRANCH>
```

If the changes have already been merged, use:

```bash
git checkout main
git pull --ff-only
```

Confirm the required files exist:

```bash
ls k8s/charts/yas-infra
ls k8s/charts/yas-platform
ls k8s/scripts
```

## 3. Review demo credentials

The defaults in `k8s/charts/yas-infra/values.yaml` and
`k8s/charts/yas-configuration/values.yaml` are classroom/demo credentials.
They must match:

```text
PostgreSQL username: yasadminuser
PostgreSQL password: admin
Redis password: redis
Keycloak bootstrap admin: admin/admin
YAS test user: admin/password
```

Do not reuse these defaults in a public or production environment.

## 4. Deploy infrastructure and dev

The script creates the required namespaces, builds local Helm dependencies,
lints both charts, deploys infrastructure, waits for it, and then deploys YAS.

```bash
bash k8s/scripts/deploy-dev.sh
```

The deployment order is:

```text
namespaces
  -> PostgreSQL + Redis + Keycloak in yas-infra
  -> shared YAS configuration
  -> backend/BFF/UI services in dev
```

PostgreSQL initializes all YAS databases only when its data directory is
empty. Its data is stored at `/var/lib/yas/postgresql` on the worker.

## 5. Verify

```bash
bash k8s/scripts/verify-dev.sh
```

Manual checks:

```bash
kubectl get pods,svc -n yas-infra
kubectl get pods,svc -n dev
helm list -A
```

All application pods should eventually become `Running` and `Ready`.

When a pod fails:

```bash
kubectl describe pod <POD_NAME> -n dev
kubectl logs <POD_NAME> -n dev
kubectl get events -n dev --sort-by=.metadata.creationTimestamp
```

Common states:

- `ImagePullBackOff`: image repository or tag does not exist.
- `CreateContainerConfigError`: a ConfigMap or Secret is missing.
- `CrashLoopBackOff`: inspect logs; infrastructure may not be ready.
- `Pending`: the worker lacks RAM/CPU or a volume cannot mount.

## 6. Open the applications

Get the worker external IP:

```bash
gcloud compute instances describe yas-worker \
  --zone=us-central1-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

Development NodePorts:

```text
Storefront: http://<WORKER_EXTERNAL_IP>:30080
Backoffice: http://<WORKER_EXTERNAL_IP>:30081
API/BFF:    http://<WORKER_EXTERNAL_IP>:30082
Keycloak:   http://<WORKER_EXTERNAL_IP>:30088
```

The storefront and backoffice NodePorts target their BFFs. Each BFF routes
`/api/*` to backend services and proxies other paths to its UI service.

Keycloak is configured primarily for in-cluster communication in this
low-cost setup. Anonymous storefront/API checks work without DNS. For a full
browser login flow, the team should later expose Keycloak through the
Ingress/Istio Gateway configured by the Service Mesh member.

## 7. Deploy one CI image tag

Jenkins builds images using the Git commit SHA. After an image such as
`<DOCKERHUB>/yas-product:a84bc32` exists:

```bash
helm upgrade --install yas-dev k8s/charts/yas-platform \
  --namespace dev \
  -f k8s/charts/yas-platform/values-dev.yaml \
  --set product.backend.image.repository=<DOCKERHUB>/yas-product \
  --set product.backend.image.tag=a84bc32 \
  --wait \
  --timeout 20m
```

Do not type the literal text `<COMMIT_ID>`. Replace it with the actual tag.

Verify the deployed image:

```bash
kubectl get deployment product -n dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

## 8. Deploy staging

The small cluster should not run full dev and staging simultaneously. Scale
dev down first:

```bash
kubectl scale deployment --all --replicas=0 -n dev
```

Build dependencies if this is a fresh clone:

```bash
bash k8s/scripts/build-helm-dependencies.sh
```

Deploy staging using a release tag:

```bash
helm upgrade --install yas-staging k8s/charts/yas-platform \
  --namespace staging \
  -f k8s/charts/yas-platform/values-staging.yaml \
  --set product.backend.image.tag=v1.0.0 \
  --wait \
  --timeout 20m
```

Staging uses NodePorts `30085`, `30086` and `30087`.

Argo CD will later replace this manual command. Jenkins should update image
tags in the GitOps repository; Argo CD should perform the cluster sync.

## 9. Rollback and removal

```bash
helm history yas-dev -n dev
helm rollback yas-dev <REVISION> -n dev
```

Remove applications:

```bash
helm uninstall yas-dev -n dev
```

Remove infrastructure:

```bash
helm uninstall yas-infra -n yas-infra
```

PostgreSQL data remains on the worker under `/var/lib/yas/postgresql`.
Deleting that directory is destructive and is not part of normal uninstall.

## 10. Evidence for the report

Capture:

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A
helm list -A
kubectl get pods,svc -n dev
```

Also capture the GCP VM list, firewall rules, successful storefront/API page,
and the output of:

```bash
helm lint k8s/charts/yas-infra
helm lint k8s/charts/yas-platform \
  -f k8s/charts/yas-platform/values-dev.yaml
```

