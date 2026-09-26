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
