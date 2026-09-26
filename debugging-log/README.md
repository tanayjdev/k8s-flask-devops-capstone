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
