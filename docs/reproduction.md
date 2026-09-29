# Reproduction Procedure

## Prerequisites
- `kind` cluster running.
- `kubectl` configured.

## Environment Assumptions
- Tested in a fresh namespace (`sep28-repro`).

## Steps
1. Create namespace: `kubectl create namespace sep28-repro`
2. Generate local secrets in `/tmp`.
3. Apply Postgres manifests and wait for rollout.
4. Apply Flask ConfigMap, SA, Deployment, and Service. Wait for rollout.
5. Deploy `reproduction-client` and execute `/health` check.

## Actual Results

### Environment
- kubectl version: v1.34.2
- Nodes: sept-k8s-control-plane, sept-k8s-worker (Ready)
- StorageClass: `standard` (rancher.io/local-path)

### Postgres
- Secret creation: Success.
- PVC state: Bound (500Mi, RWO).
- Postgres rollout: Successfully rolled out.
- Postgres EndpointSlice: Populated (IPv4 Port 5432).

### Flask
- Flask Secret: Success.
- ConfigMap: Created.
- ServiceAccount: Created (Namespace-neutral).
- Flask rollout: Successfully rolled out.
- Flask EndpointSlice: Populated (IPv4 Port 5000).

### Application
- Actual `/health` output: `{"database":"connected","status":"healthy"}`

### Result
PASS

## Cleanup
Deleted via `kubectl delete namespace sep28-repro` and removed `/tmp` secrets.
