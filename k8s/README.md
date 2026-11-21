# k8s/

Kustomize manifests for the SmartFit backend (one Deployment + Service per service).

| Path | Purpose |
|---|---|
| `base/` | Shared manifests: namespace, `smartfit-config` ConfigMap, 8 services |
| `overlays/local/` | Local cluster demo (minikube / k3s / Docker Desktop K8s). Gateway on NodePort **30080**. |
| `overlays/production/` | AWS EKS target design (SRDS Fig 5.2) — documented, **not deployed**. |

## Local demo

```bash
docker compose build                                 # builds smartfit/<svc>:dev images
cp k8s/overlays/local/secrets.env.example k8s/overlays/local/secrets.env   # fill in
kubectl apply -k k8s/overlays/local
kubectl -n smartfit get pods
```

Day-to-day development uses `docker compose up` instead — Kubernetes is for the deployment demo.

## Validate without a cluster

```bash
kubectl kustomize k8s/overlays/local       # needs secrets.env to exist
kubectl kustomize k8s/overlays/production
```
