# Kubernetes Troubleshooting Reference
Built September 19, 2026 — consolidates Sep 1–18 debugging patterns.

## First 5 Minutes — Triage Flow
1. `kubectl get pods` — what STATUS?
   - `Pending` → go to §Scheduling
   - `ImagePullBackOff` / `ErrImagePull` → go to §Image
   - `CrashLoopBackOff` → go to §Container Runtime
   - `Running` but `0/1 READY` → go to §Readiness
   - `Running`, all Ready, but app unreachable → go to §Networking / §Service
   - `CreateContainerConfigError` → go to §Configuration
2. If the object involved is a Service → go to §Service
3. If the error mentions `Forbidden` → go to §RBAC
4. If the object is a Job/CronJob → go to §Batch Workloads

## Command-Selection Matrix
| Symptom | First Command | What It Proves |
|---|---|---|
| Pod Pending | `kubectl describe pod <pod>` | Scheduling reason from Events |
| Container not starting | `kubectl describe pod <pod>` | Image/config/init failure clues |
| Container restarting | `kubectl describe pod <pod>` + NAME/UID check | Container restart vs Pod replacement |
| Service unreachable | `kubectl get endpoints <svc>` / EndpointSlice | Whether usable backends exist |
| DNS uncertain | `nslookup` from a test Pod, then direct Pod-IP test | DNS resolution vs actual connectivity |
| Forbidden | `kubectl auth can-i <verb> <resource> --as=<identity> -n <ns>` | Ground-truth authorization decision |
| Job not completing | `kubectl get pods -l job-name=<job>` | One Pod vs multiple Pod identities |
| PVC stuck | `kubectl describe pvc <pvc>` | Provisioning/binding Events and state |

## §Scheduling (Sep 12, 14)
**Symptom:** Pod Pending
**First evidence:** `kubectl describe pod <pod>` → Events
**Decision tree:**
- "Insufficient cpu/memory" → resource-fit problem → compare Pod requests against node Allocatable
- "node(s) had untolerated taint" → taint/toleration problem → inspect node taints
- "didn't match Pod's node affinity/selector" → selector/affinity mismatch → inspect node labels

## §Image / Container Startup (Sep 4, 8)
**Symptom:** ImagePullBackOff / ErrImagePull
**Evidence:** `kubectl describe pod <pod>` → Events → exact image/tag
**Root-cause classes:** bad image/tag, private registry authentication, network/registry connectivity

**Symptom:** Init:Error / Init:CrashLoopBackOff
**Evidence:** `kubectl logs <pod> -c <init-container>`
**Root-cause class:** The init container's own command is failing. The main container is blocked waiting for init completion.

## §Container Runtime / Restart (Sep 4, 12, 18)
**Symptom:** RESTARTS incrementing
**Evidence Step 1:** Check Pod NAME + UID.
**Evidence Step 2:** `kubectl describe pod <pod>` → Last State → Reason
**Decision tree:**
- Reason: OOMKilled → investigate container memory limit/usage AND node memory pressure.
- Reason / Events indicate probe failure → investigate liveness probe.
- Repeated exits without probe evidence → investigate the application's own crash.
**Mechanism verification:** Same NAME + UID = container restart. New NAME / UID = Pod replacement.

## §Readiness (Sep 11)
**Symptom:** Running, READY 0/1, and the Pod is absent from usable Service backends.
**Evidence:** `kubectl describe pod <pod>` → Events → readiness probe failure reason
**Lesson:** A readiness failure does not automatically mean the container should be restarted. The system correctly removes an unhealthy backend from Service traffic while the Pod remains Running.

## §Configuration (Sep 10)
**Symptom:** CreateContainerConfigError
**Evidence:** `kubectl describe pod <pod>` → Events
**Typical root causes:** ConfigMap/Secret key typo, referenced object missing, wrong namespace.

## §Service (Sep 9, 16)
**Symptom:** Service unreachable
**STEP 1 — inspect backend state:** `kubectl get endpoints <svc>`.
- NO USABLE READY ENDPOINTS → inspect selector, labels, readiness, EndpointSlice conditions.
- POPULATED READY ENDPOINTS → continue with port/connectivity checks.
**STEP 2 — direct Pod-IP test:** Bypass the Service.
- FAILS → investigate Pod-network/connectivity path.
- SUCCEEDS → focus on Service-specific configuration (targetPort, port mapping, forwarding behavior).
**STEP 3 — DNS:** A successful lookup proves name resolution. It does NOT prove Service health, ready backends, or application health.

## §RBAC (Sep 17–18)
**Symptom:** Forbidden
**Evidence:** `kubectl auth can-i <verb> <resource> --as=<identity> -n <namespace>`
**Decision tree:**
- "no" confirmed as intentional → first determine whether the request SHOULD actually be denied. Forbidden is not automatically a bug.
- Works in one namespace, not another → inspect the effective binding (RoleBinding vs ClusterRoleBinding).

## §Batch Workloads (Sep 18)
**Symptom:** Job stuck / not completing
**Evidence:** `kubectl get pods -l job-name=<job>`
- MULTIPLE distinct Pod NAMEs → restartPolicy: Never → Job controller creates replacement Pods.
- ONE Pod NAME with RESTARTS climbing → restartPolicy: OnFailure → kubelet restarts the container in place.
- Neither → investigate whether a CronJob trigger was skipped (`concurrencyPolicy: Forbid`).

## §Storage (Sep 15)
**Symptom:** PVC Pending
**Evidence:** `kubectl describe pvc <pvc>` → Events
- No Events + no consuming Pod → WaitForFirstConsumer is expected.
- Events mention missing StorageClass → inspect StorageClass name, provisioner, and Events. Do not assume provisioning is guaranteed.

## Debugging Log Entry Template
## [Date] — [One-line title]
**Symptom:**
**Observation:**
**Hypothesis:**
**Evidence:**
**Root Cause:**
**Fix:**
**Verification:**
**Lesson:**

## Live Verification Scenarios
### Scenario 1: Ambiguous Pending Pod
**Actual Event Output:** 
Warning  FailedScheduling  2s    default-scheduler  0/2 nodes are available: 1 Insufficient memory, 1 node(s) had untolerated taint(s). preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.
**Diagnosis:** Insufficient memory. Diagnosed via Pending → §Scheduling → describe pod → Events.

### Scenario 2: Ambiguous Service Failure
**Symptom:** Service request fails.
**Observation:** `kubectl get endpoints` showed populated endpoints (mapped to wrong port).
**Evidence:** Direct Pod-IP:80 succeeded, proving the Pod and CNI are healthy.
**Diagnosis:** The fault lies strictly in the Service configuration.
**Fix:** Corrected `targetPort` from 12345 to 80.
