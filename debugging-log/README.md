# Debugging Log

Genuine incident count: 8

## 26 Sept 2026 — Independent Engineering Challenge

### 1. Symptom
Cluster-wide outage. All new pods were stuck in `Pending`, old pods in `Terminating`, and service resolution failed with `bad address`.

### 2. Hypotheses Considered
1. The Kubernetes scheduler cannot place pods due to insufficient resources or node taints.
2. The application itself is crash-looping.
3. The cluster DNS is failing.

### 3. Evidence That Eliminated Wrong Hypotheses
- `kubectl describe pod` revealed `FailedScheduling` events explicitly citing `untolerated taint(s)`. This eliminated an application-layer fault and proved it was a node-level scheduling issue.

### 4. Decisive Evidence
- `kubectl get nodes` showed `sept-k8s-worker` as `NotReady` with `node.kubernetes.io/unreachable` taints. 
- Host-level `docker ps` confirmed the underlying worker node container had `Exited (128)`.
- After node recovery, DNS resolution failed (`wget: bad address`), indicating stale CoreDNS routing.

### 5. Root Cause
A host-level crash of the Kubernetes worker node (Docker container stopped abruptly) caused the control plane to mark the node unreachable and evict workloads. The violent crash also left stale shim locks and corrupted the CoreDNS routing state.

### 6. Fix Applied
Restarted the host Docker daemon to clear stale runtime locks, restarted the `sept-k8s-worker` container via `docker start`, and restarted cluster DNS via `kubectl rollout restart deployment coredns -n kube-system`.

### 7. Verification
- /health result: Database connected (Proven by Flask Pods successfully passing their `/health` Readiness probe and reaching 1/1 Ready state).
- Flask Service Ready EndpointSlice result: Populated with healthy Pod IPs.
- Additional verification: Node returned to `Ready` status.
  
### 8. Interview-Quality Explanation
I first observed a cluster-wide outage where all new pods were stuck in `Pending` and old pods were stuck in `Terminating`. I hypothesized an infrastructure or scheduling fault because `Pending` indicates the scheduler is refusing to place workloads. I tested this by checking Pod Events, which showed `FailedScheduling` due to untolerated node taints. The decisive evidence came when `kubectl get nodes` showed the worker node as `NotReady`, and a host-level `docker ps` check confirmed the worker container had abruptly crashed. Therefore, the root cause was a catastrophic host-level node failure. I corrected it by restarting the Docker daemon and the worker container, followed by restarting CoreDNS to fix the resulting internal DNS outage. I verified the remediation by watching the node become `Ready` and all Pods successfully pass their database-aware readiness probes to reach `1/1 Running`, completely restoring application health.
