# Kubernetes Debugging Log — September 2026

## 1 Sept 2026 — YAML indentation failure

**Symptom:** YAML parsing failed.

**Observation:** The `labels` key had a literal tab character
instead of space-based indentation.

**Hypothesis:** YAML parser rejected the tab indentation.

**Evidence:** 
`kubectl apply -f broken.yaml --dry-run=client`

**Root Cause:** Tab used for indentation.

**Fix:** Replaced the tab with two spaces.

**Verification:** Re-ran the dry-run and confirmed the
YAML parser error disappeared.

**Prevention:** Enable visible whitespace in the editor and
use YAML lint/validation in automation later.

**Lesson:** Always identify the failure layer first:
YAML syntax/parsing is different from Kubernetes resource validation.

## 2 Sept 2026 — Scale-to-zero false alarm

**Symptom:** All Pods disappeared.

**Observation:** The Deployment still existed.

**Hypothesis:** The controller was honoring a desired
replica count of zero.

**Evidence:** 
`kubectl describe deployment recon-demo | grep Replicas`
confirmed the Deployment had zero desired/updated/available
replicas.

**Diagnosis:** No Kubernetes failure occurred. The desired
state itself had been changed to zero.

**Fix:** Scaled the Deployment back to three replicas.

**Verification:** Pods were recreated and converged back
toward the desired count.

**Lesson:** Never diagnose “no Pods” without checking the
declared desired state.

## 3 Sept 2026 — ReplicaSet selector/template mismatch

**Symptom:** ReplicaSet creation was rejected by the Kubernetes API.

**Observation:** The ReplicaSet selector used `app=wbe`,
while the Pod template used `app=web`.

**Hypothesis:** The selector/template label relationship was invalid.

**Evidence:** Compared:
- `spec.selector.matchLabels.app = wbe`
- `spec.template.metadata.labels.app = web`

**Diagnosis:** The selector did not match the template label.

**Root Cause:** Typo: `wbe` instead of `web`.

**Fix:** Changed the selector value to `app=web`.

**Verification:** ReplicaSet was created successfully and
the expected Pods appeared with `app=web`.

**Rebuild Verification:** Deleted the ReplicaSet and recreated it
from the corrected manifest; behavior remained reproducible.

**Lesson:** Selectors are not just descriptive text. They define
matching relationships, and Kubernetes validates important
selector/template consistency before accepting the workload.

## 4 Sept 2026 — Init container failure blocking main container start

**Symptom:** Pod init-demo stuck at 0/1, status showed Init:
prefix, never reached Running.

**Observation:** kubectl describe pod showed BackOff events for
the init container "setup".

**Hypothesis:** Init container was failing, and initialization
was not completing — main container cannot start until init
containers complete successfully.

**Evidence:** kubectl logs init-demo -c setup showed no output
(command was `exit 1`); kubectl describe pod init-demo Events
section confirmed repeated restart attempts on the init container.

**Root Cause:** Init container command deliberately set to exit 1.

**Fix:** Restored the correct command (write shared file).

**Verification:** Pod reached 1/1 Running; main container logs
confirmed it read the file the init container wrote.

**Rebuild Verification:** Deleted and recreated the Pod from the
corrected manifest; same successful behavior reproduced.

**Lesson:** A failing init container blocks ALL main containers
in the Pod — the ordering guarantee (init completes before main
starts) is absolute, not best-effort. Retry behavior for init
containers should not be assumed identical to ordinary
app-container restart handling.

## 5 Sept 2026 — Standalone ReplicaSet, ownership/adoption, template behavior, and label-removal debugging

**Scope:** Direct ReplicaSet reconciliation without a Deployment.

**Baseline:** Created a standalone ReplicaSet with `replicas: 2`,
selector `app=web`, and an nginx Pod template.

**Proof 1 — Standalone reconciliation:** Scaled the ReplicaSet from
2 to 4 directly with `kubectl scale`. ReplicaSet created the missing
Pods without any Deployment involved.

**Ownership/selection lesson:** The ReplicaSet selector identifies
matching Pods, while `ownerReferences` records controller ownership.
These are related but distinct concepts. A pre-existing matching Pod
was eligible for adoption and the ReplicaSet established ownership
through `ownerReferences` rather than creating a duplicate third Pod.

**Proof 2 — Template behavior:** Changed the ReplicaSet template from
`nginx:1.25` to `nginx:1.26`. Existing Pods remained on `nginx:1.25`.
After scaling up, only the newly created Pod used `nginx:1.26`.

**Symptom — Label mutation:** Removed `app=web` from one
ReplicaSet-managed Pod.

**Observation:** The target Pod continued running but no longer
appeared under `kubectl get pods -l app=web`. The ReplicaSet observed
fewer selected replicas and created a replacement Pod.

**Hypothesis:** Removing a selector label changes selector membership.
A running Pod can therefore leave the controller's selected workload
without being deleted.

**Evidence:** Compared filtered and unfiltered Pod lists, observed the
new replacement Pod, and inspected the target Pod's labels and
`ownerReferences`.

**Diagnosis:** The target Pod no longer matched the ReplicaSet
selector. During reconciliation the controller could release its
ownership, while the ReplicaSet created a new matching Pod to restore
the desired selected replica count.

**Root Cause:** `kubectl label pod <name> app-` removed the label used
by the ReplicaSet selector.

**Fix:** Restored `app=web`, then rebuilt the experiment cleanly to
return to a deterministic two-Pod state.

**Lesson:** Selection and ownership are separate pieces of Kubernetes
state. Label changes can alter controller membership and cause
reconciliation even when no Pod deletion occurred.

## 7 Sept 2026 — Deployment rollout, revision history, rollback, and maxSurge/maxUnavailable validation

**Scope:** Deployment deepening — Deployment → ReplicaSet → Pod,
controlled rollout, revisions, rollback, and strategy validation.

**Ownership model:** Deployment records ownership of its ReplicaSets
through `ownerReferences`, while ReplicaSets record ownership of
their Pods. Ownership is distinct from selection and reconciliation;
the controller combines these concepts to manage desired state.

**Proof 1 — Ownership chain:** Created `deploy-demo` and inspected
Deployment → ReplicaSet and ReplicaSet → Pod `ownerReferences`.

**Proof 2 — pod-template-hash:** Inspected Deployment-managed Pods and
ReplicaSets and observed the automatically generated
`pod-template-hash` label.

**Proof 3 — Rollout:** Changed the Deployment image from
`nginx:1.25` to `nginx:1.26`. Observed the Deployment reconcile its
ReplicaSets so the target revision scaled up while the previous
revision scaled down.

**Important mechanism note:** Do not generalize this as
"every template change always creates a brand-new ReplicaSet object."
The Deployment reconciles toward the required Pod-template state,
and an existing matching ReplicaSet can be reused in revision/
rollback scenarios.

**Proof 4 — Revision history:** `kubectl rollout history` showed
multiple revisions after the Pod-template change.

**Proof 5 — Rollback:** `kubectl rollout undo` returned the Deployment
to the earlier `nginx:1.25` template state. The rollback was performed
through Deployment revision reconciliation rather than manual
ReplicaSet scaling.

**Validation failure:** Applied a RollingUpdate strategy with
`maxSurge: 0` and `maxUnavailable: 0`.

**Observation:** The API rejected the invalid configuration.

**Hypothesis:** With neither surge capacity nor unavailable capacity
allowed, the rollout has no valid replacement path.

**Root Cause:** Invalid zero/zero RollingUpdate configuration.

**Fix:** Changed to `maxSurge: 1`, `maxUnavailable: 0`.

**Lesson:** Deployment combines selection, ownership, and
reconciliation. ReplicaSets provide Pod-count enforcement, while
Deployment adds controlled rollout, revision history, and rollback.

## 8 Sept 2026 — Rollout stuck, Scenario A: bad image reference

**Symptom:** `kubectl rollout status` did not complete after a Deployment image update.

**Observation:** New Pods entered `ImagePullBackOff` / `ErrImagePull`.

**Hypothesis:** The new image reference could not be pulled.

**Evidence:** `kubectl describe pod` Events showed an image-pull failure such as `Failed to pull image` / manifest-not-found style registry errors.

**Diagnosis:** The container process never started because the requested image could not be obtained.

**Root Cause:** Deliberately invalid image tag: `nginx:this-tag-does-not-exist-12345`.

**Immediate Fix:** Rolled back the Deployment to the known-good revision to restore service stability.

**Important distinction:** Rollback restored the known-good service state but did NOT fix the underlying defect; the invalid image reference remained the root-cause defect to be addressed separately.

**Verification:** Deployment rollout completed and Pods returned to the known-good image.

**Lesson:** A stuck Deployment rollout is a symptom. `kubectl get pods` can immediately identify an image-layer failure through `ImagePullBackOff` / `ErrImagePull`.

## 8 Sept 2026 — Rollout stuck, Scenario B: readiness-gate failure

**Symptom:** `kubectl rollout status` again failed to complete, producing the same top-level "stuck rollout" symptom as Scenario A.

**Observation:** New Pods were `Running`, but remained `0/1 Ready`. This was different from Scenario A because the image pull and container startup had succeeded.

**Hypothesis:** The failure was at the readiness layer.

**Evidence:** `kubectl describe pod` Events showed the readiness HTTP probe failing with HTTP status code `404`.

**Diagnosis:** nginx was running, but the readiness probe requested a nonexistent path. The HTTP probe therefore failed and the Pod did not become Ready.

**Root Cause:** `readinessProbe.httpGet.path` was intentionally set to `/this-path-does-not-exist`.

**Immediate Fix:** Rolled back the Deployment first to restore stability.

**Fix Forward:** Separately corrected the probe path to `/` and reapplied the Deployment.

**Verification:** New Pods became `Running` and `1/1 Ready`; the Deployment rollout completed successfully.

**Rebuild Verification:** Deleted the entire Deployment and recreated it from the corrected manifest. The final configuration successfully produced three `Running`, `1/1 Ready` Pods.

**Scope note:** Readiness probes were used only as a minimal prerequisite for this failure diagnosis. Deep probe design, semantics, tuning, startup/liveness interactions, and advanced troubleshooting remain deferred to the dedicated Sept 11 probe day.

**Lesson:** Identical top-level symptoms can have different root causes. Pod STATUS/READY state provides the first diagnostic layer, and `kubectl describe pod` Events provide evidence.

## 9 Sept 2026 — Service selector mismatch (Exercise 1)
**Symptom:** wget through Service timed out.
**Observation:** `kubectl get endpoints` showed `<none>` despite Service having a valid ClusterIP.
**Hypothesis:** Selector matches no Pods.
**Evidence:** `kubectl get pods -l app=wrong-label` returned "No resources found"; `kubectl get pods -l app=web-app` showed 3 Pods existed but weren't selected.
**Root Cause:** Service selector value didn't match Pod labels.
**Fix:** Corrected selector to `app=web-app`.
**Verification:** Endpoints populated with 3 entries.
**Lesson:** Same selection-not-ownership mechanism as Sep 3/5's ReplicaSet work, now confirmed at Service level.

## 9 Sept 2026 — Service targetPort mismatch (Exercise 2)
**Symptom:** wget connection refused (fast, not a timeout — different signature from the selector-mismatch failure).
**Observation:** Endpoints WERE populated (`<pod-ip>:8080`), ruling out a selection problem immediately.
**Hypothesis:** Wrong port being forwarded to.
**Evidence:** Container's actual containerPort was 80, not 8080.
**Root Cause:** targetPort didn't match the application's listening port. Kubernetes does not validate this at apply time.
**Fix:** Corrected targetPort to 80.
**Verification:** wget succeeded.
**Lesson:** Endpoints populated ≠ traffic will succeed — endpoint presence only proves selection worked, not that the port wiring is correct.

## 9 Sept 2026 — DNS resolves, application still fails (Exercise 4)
**Symptom:** nslookup succeeded; wget through the same name failed.
**Observation:** Two completely separate outcomes for what looks like "the same Service.”
**Diagnosis:** DNS resolution succeeded, meaning the DNS system successfully returned an address for the Service name. That did not prove that ready backends existed, that targetPort was correct, or that the application was healthy.
**Lesson:** Never stop diagnosing at "DNS resolves" — DNS is only one step in the Service access chain.

## 10 Sept 2026 — ConfigMap key typo blocking Pod start
**Symptom:** Pod stuck in `CreateContainerConfigError`.
**Observation:** `kubectl describe pod` Events named the missing key.
**Root Cause:** Typo `GREETINGG` vs actual key `GREETING`.
**Fix:** Corrected key name.
**Verification:** Pod reached Running, env var populated correctly.
**Lesson:** Same typo-driven failure class as Sep 3's selector mismatch — Kubernetes validates key references and fails fast at container-start rather than silently proceeding.

## 10 Sept 2026 — ConfigMap update does not change running env vars
**Observation:** Updated ConfigMap value; running Pod's env var stayed unchanged. Mounted file eventually updated (~60s), env var required a rollout restart to pick up the new value.
**Lesson:** Env vars are injected once at container start. Mounted files sync periodically via kubelet but require the application itself to notice and reload — file-update ≠ app-reload. This distinction directly affects how config changes should be rolled out in real deployments.

## 10 Sept 2026 — Wrong Secret key reference
**Symptom:** Pod stuck in `CreateContainerConfigError` (same signature as the ConfigMap key failure).
**Root Cause:** Typo in `secretKeyRef.key`.
**Fix:** Corrected key name.
**Lesson:** Secret and ConfigMap key-reference failures produce identical diagnostic signatures — the fix path (`describe pod` → read Events → check exact key name) is the same regardless of which object type is involved.

## 11 Sept 2026 — Readiness failure affects Service endpoint readiness
**Symptom:** After deleting one Pod's index.html, that Pod showed 0/1 READY while STATUS remained Running.
**Observation:** `kubectl get endpoints web-app-svc` dropped from 3 to 2 entries after the Pod became NotReady.
**Evidence:** The affected Pod remained present and Running, while its Service backend endpoint was no longer considered ready for normal Service traffic.
**Diagnosis:** The readiness failure changed the Pod's Ready state. The Pod object itself remained Running and its container was NOT restarted.
**Fix:** Restored index.html; the Pod became Ready again and the Service backend endpoint returned to the ready set.
**Lesson:** Readiness controls whether a Pod-backed Service endpoint is considered ready for normal Service traffic. A readiness failure does not delete the Pod or restart its container.

## 11 Sept 2026 — Liveness failure restarts container in place
**Symptom:** RESTARTS count incremented on liveness-demo.
**Observation:** `kubectl describe pod liveness-demo` showed repeated liveness probe failures followed by container restart events.
**Evidence:** Pod NAME and UID were identical before and after the restart (recorded and compared explicitly).
**Root Cause:** The liveness probe path deliberately pointed to a nonexistent path.
**Fix:** Corrected the liveness probe path to `/`.
**Verification:** The same Pod object remained in place while the container restarted; after correcting the probe, RESTARTS stopped increasing.
**Lesson:** A liveness failure causes kubelet to restart the container in place. It does NOT create a replacement Pod object.

## 11 Sept 2026 — startupProbe prevents premature liveness restarts during slow start
**Symptom:** A container with a 20-second artificial startup delay and an aggressive liveness probe (without a startupProbe) began restarting before nginx finished starting.
**Observation:** RESTARTS incremented within the first ~10 seconds, well before the 20-second sleep completed.
**Root Cause:** The liveness probe began checking before the application had completed its legitimate startup period.
**Fix:** Added a startupProbe with enough allowance (`failureThreshold: 10` × `periodSeconds: 3` = up to 30 seconds) to cover the intended startup window. Liveness checking was held off until the startup success.
**Verification:** The same slow-start command completed startup without premature liveness restarts; RESTARTS remained 0.
**Lesson:** startupProbe protects legitimately slow-starting containers from premature liveness failures. It allows the application time to initialize without weakening the later liveness failure detection window.

## 12 Sept 2026 — OOMKilled vs CPU throttled, same tool, different enforcement
**Symptom (memory):** RESTARTS incremented on oom-demo; same NAME+UID before/after (Sep 4 technique reused).
**Evidence:** `kubectl describe` showed Reason: OOMKilled, Exit Code: 137 (SIGKILL).
**Root Cause:** `stress --vm-bytes 250M` exceeded a 100Mi memory limit.
**Fix:** Raised memory limit to 300Mi.
**Contrast (CPU):** Identical stress tool, `--cpu 1` against a 100m CPU limit — RESTARTS stayed 0, Pod never killed, only slowed.
**Lesson:** Memory is incompressible (OOM-killed on excess); CPU is compressible (throttled, stays alive). Same violation pattern, fundamentally different enforcement mechanism.

## 12 Sept 2026 — ResourceQuota admission-time rejection
**Symptom:** `kubectl run` failed immediately with "exceeded quota".
**Root Cause:** Namespace pod count already at quota's hard limit (4).
**Lesson:** ResourceQuota enforcement happens at the API server's admission stage — before scheduling, before the object is ever created. Different failure category entirely from a Pod that IS created but stays Pending (that's Sep 14's territory).

## 14 Sept 2026 — Pod Pending due to stacked taints, no tolerations
**Symptom:** `notoleration-pod` stuck Pending indefinitely.
**Observation:** `kubectl describe pod` Events named BOTH nodes' taints explicitly as the exclusion reasons.
**Root Cause:** No tolerations set; both control-plane (default kind taint) and worker (deliberately added) were excluded.
**Fix:** Added a toleration matching the worker's specific taint.
**Verification:** Pod landed on worker — control-plane remained excluded since its taint wasn't separately tolerated.
**Lesson:** Toleration grants permission, not attraction — it only landed on worker because worker was the sole remaining viable node, not because tolerating pulled it there.
