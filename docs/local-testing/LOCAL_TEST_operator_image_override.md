# Local test: can we drop Kyverno and set the operator image via OLM?

**Cluster:** local CRC (OpenShift 4.18.2) — a dev/test cluster.
**Date of run:** run 1 captured in an earlier session; run 2 on 2026-07-29.
**Short answer:** **Yes — via a CSV patch, not via the Subscription.**
`RELATED_IMAGE_MANAGER` does **not** change this operator's own image (run 1, §4a), but
**patching the installed ClusterServiceVersion does** (run 2, §8) and OLM does not revert it.
The ZAP logging env vars work through OLM, and resource limits work too (with a caveat on CRC).

> **§5 of run 1 is superseded.** It concluded "keep Kyverno — it is required." That was correct
> for the mechanism tested at the time (`spec.config`), but wrong as a general claim: run 2
> proves a CSV patch replaces Kyverno entirely. See §8.

---

## 1. What we wanted to find out

Today the operator runs our custom image `docker.io/ephico2real/namespace-configuration-operator:latest`.
That image is put in place by a **Kyverno** policy that rewrites the operator's image at
admission time. We wanted to know: **can we remove Kyverno and instead set the image the
"native" OLM way**, using the `RELATED_IMAGE_MANAGER` env var in the Subscription?

## 2. How the image is set today (baseline)

| Layer | manager image |
|---|---|
| What OLM installs (the CSV) | `quay.io/redhat-cop/namespace-configuration-operator@sha256:49ed7d61…` (upstream) |
| What actually runs (after Kyverno) | `docker.io/ephico2real/namespace-configuration-operator:latest` (ours) |

Three Kyverno ClusterPolicies were involved (all backed up to
[`kyverno-backup/`](kyverno-backup/) before we touched anything):

- `replace-operator-image-to-dockerhub` — swaps the image to ours
- `inject-dockerhub-secret` — adds the Docker Hub pull secret
- `configure-operator-log-level` — sets the log level

## 3. What we did (step by step)

1. **Backed up** the 3 Kyverno policies to files.
2. **Checked** our quay image is public/pullable (it is — `sha256:8a65b31…`).
3. **Deleted** the 3 Kyverno policies.
4. **Applied** the Helm chart's Subscription, which adds to `spec.config`:
   - `env`: `ZAP_LOG_LEVEL=info`, `ZAP_DEVEL=false`, `RELATED_IMAGE_MANAGER=quay.io/ephico2real/…:latest`
   - `resources`: requests 250m/500Mi, limits 2/4Gi
5. **Watched** what image the operator actually ran.

## 4. What we found

### 4a. `RELATED_IMAGE_MANAGER` does NOT change the operator image ❌

The env var was injected into the deployment (we confirmed it was there), **but the
manager image stayed upstream**:

```text
env on the deployment:  ZAP_LOG_LEVEL, ZAP_DEVEL, RELATED_IMAGE_MANAGER  ✅ injected
manager image:          quay.io/redhat-cop/...@sha256:49ed7d61…          ❌ unchanged (upstream)
```

**Why:** `RELATED_IMAGE_*` env vars tell an operator which image to use for the *things it
deploys* (its "operands"). This operator only creates RBAC and NetworkPolicy objects — it
deploys **no pods** — so `RELATED_IMAGE_MANAGER` has nothing to act on. It does **not**
set the operator's *own* container image. Only an admission mutation (Kyverno) or a custom
catalog can do that.

### 4b. The ZAP logging env vars DO work ✅

`ZAP_LOG_LEVEL` and `ZAP_DEVEL` were injected correctly through `spec.config.env`. So the
chart **can replace** the `configure-operator-log-level` Kyverno policy.

### 4c. `resources` work — but watch out on CRC ⚠️

The resource requests/limits applied fine, **but on CRC** (one small node, already ~90%
CPU) the rolling update got stuck: OpenShift briefly needs **two** operator pods at once
(old + new) during a rollout, and the second pod couldn't fit → `Pending: Insufficient
cpu`. Two lessons:

- On a properly-sized cluster this is fine; on CRC, use smaller requests for testing.
- **OLM does not cleanly remove `resources` once set** via `spec.config` — unsetting it in
  the Subscription left the value on the deployment. A full clean-up needed a CSV
  reinstall (see §6).

## 5. Conclusion

- **Keep Kyverno** for the image swap — it is required. (`replace-operator-image-to-dockerhub`
  + `inject-dockerhub-secret`.)
- The Helm chart's `spec.config.env` **can** own the **log level** (ZAP) and **resources**,
  so the `configure-operator-log-level` Kyverno policy is replaceable by the chart.
- The only other way to drop Kyverno for the image would be a **custom CatalogSource** whose
  CSV points at our image — a bigger piece of work, out of scope for this test.

## 6. How we put everything back (restore)

The operator is fully restored — pod `2/2 Running`, leader elected, image
`docker.io/ephico2real/...:latest`. Steps taken:

1. Restored `replace-operator-image-to-dockerhub` + `inject-dockerhub-secret` from backup.
2. Because OLM would not cleanly drop the `resources` it had applied, we deleted the CSV and
   recreated a **minimal Subscription** (no `spec.config`, `installPlanApproval: Automatic`).
   OLM reinstalled the operator cleanly.
3. Verified: single healthy pod, correct (our) image via Kyverno.

> Note: `configure-operator-log-level` was **not** restored — the chart's ZAP env now covers
> it. Restore it from `kyverno-backup/` if you prefer Kyverno to own the log level.

## 7. What this means for the chart

- `subscription.relatedImageManager` is kept as a configurable env for completeness, but it
  is **defaulted off** and documented as **not** an image override for this operator.
- `subscription.zapLogLevel` / `zapDevel` and `subscription.resources` are the genuinely
  useful `spec.config` knobs.

---

# Run 2 (2026-07-29) — patching the CSV instead

## 8. The CSV patch works ✅

Run 1 only tested `Subscription.spec.config`. It never tested the layer *below* it: the CSV
that OLM installs. OLM treats `spec.install.spec.deployments[]` in the installed CSV as the
source of truth for the operator Deployment, so patching the image there is a supported-shaped
change even though there is no Subscription field for it.

**Method.** Deleted the `replace-operator-image-to-dockerhub` Kyverno policy first — it mutates
Deployment *and* Pod on CREATE/UPDATE, so leaving it in place would have masked the result and
produced a false positive. Then patched the source CSV's `manager` container.

```bash
oc patch csv namespace-configuration-operator.v1.2.6 -n namespace-configuration-operator \
  --type=json -p '[{"op":"add",
    "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image",
    "value":"quay.io/ephico2real/namespace-configuration-operator:latest"}]'
```

**Result — propagated in under 10 seconds:**

```text
t=10s  csv    = quay.io/ephico2real/namespace-configuration-operator:latest
       deploy = quay.io/ephico2real/namespace-configuration-operator:latest
```

The running pod's `imageID` was `quay.io/ephico2real/namespace-configuration-operator@sha256:8a65b3196b29c8a183165e1e3143051782b30bbb51392a0fbdf903430e262cdd`
— matching the digest returned by the quay registry API for `:latest`, with Kyverno's image
policy deleted. So the CSV patch alone put our image in production.

**OLM did not revert it.** Watched for 10 minutes at 20s intervals: `generation=2`,
`phase=Succeeded`, CSV and Deployment both holding our image the whole time. OLM re-fetches
nothing for an already-installed CSV.

## 9. Only the SOURCE CSV matters

NCO installs AllNamespaces, so OLM copies the CSV into **every** namespace (137 of them on this
cluster). The copies carry `olm.copiedFrom=namespace-configuration-operator` and are re-synced
replicas — patching them is pointless. Only the CSV in the install namespace, which owns the
Deployment, needs the patch. The chart's Job asserts `olm.copiedFrom` is empty and refuses to
patch a copy.

## 10. ⚠️ A bad image WEDGES OLM — the important finding

While restoring, a deliberately-invalid test image (`registry.example.com/someone-else/nco:v9`)
reached the Deployment. Reverting the CSV to upstream **did not recover the operator**:

```text
CSV image  : quay.io/redhat-cop/...@sha256:49ed7d61   <- reverted
deploy img : registry.example.com/someone-else/nco:v9 <- still bad
CSV phase  : Installing | InstallWaiting | waiting for 1 outdated replica(s) to be terminated
pod        : ImagePullBackOff
```

**Why:** OLM applies the install strategy on the `Pending -> Installing` transition, not on
every sync. Once the rollout cannot finish, the CSV parks in `InstallWaiting` and OLM stops
re-applying the Deployment — so it never picks up the corrected CSV. It is a deadlock: OLM
waits for a rollout that can only be fixed by OLM.

**Recovery** is to patch the Deployment directly, which starts a fresh rollout:

```bash
oc set image deploy/namespace-configuration-operator-controller-manager \
  -n namespace-configuration-operator manager=<last-known-good-image>
```

This is why the chart's Job rolls back **both** the CSV and the Deployment on a failed rollout,
rather than the CSV alone. Verified with a deliberately unpullable tag: the Job patched, waited
90s, rolled both back, and the cluster returned to `Succeeded` / `1/1` on its own.

## 11. Chart implementation and what was verified

`operatorImage.enabled=true` renders a ServiceAccount, Role, RoleBinding, script ConfigMap, a
post-install/post-upgrade hook Job, and an optional reconcile CronJob. Verified on-cluster:

| Path | Result |
|---|---|
| CSV already at target | `already at target image; skipping patch`, exit 0, no restart |
| CSV at upstream | patched → propagated → rolled out in ~32s |
| CSV at an unrelated image | **refused**, job failed, CSV left untouched |
| Target image unpullable | **rolled back** CSV + Deployment, cluster self-recovered |

Container indices are discovered at runtime, never hardcoded — in v1.2.6 `manager` is
`containers[1]` and `kube-rbac-proxy` is `containers[0]`.

## 12. Kyverno vs the CSV patch

| | Kyverno policy | CSV patch Job |
|---|---|---|
| Enforcement | Continuous, at admission | One-shot per run |
| Survives OLM operator upgrade | Yes | **No** — needs the reconcile CronJob |
| Extra cluster dependency | Requires Kyverno | None (`openshift/cli` image only) |
| Pull secret handling | Separate policy | `operatorImage.imagePullSecret` |
| Blast radius if misconfigured | Admission-time reject/mutate | Can wedge OLM (mitigated by rollback) |

The default quay image is public, so `inject-dockerhub-secret` is not needed either — both
Kyverno policies can be retired by switching to quay. `operatorImage.enabled` is **off by
default**; enabling it is a deliberate choice.

> Cluster was restored to baseline after run 2: CSV back to the upstream digest, `Succeeded`,
> a single pod on `docker.io/ephico2real/…:latest` via the restored Kyverno policies, and no
> leftover image-override objects.
