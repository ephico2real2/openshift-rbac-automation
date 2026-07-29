# Local test: can we drop Kyverno and set the operator image via OLM?

**Cluster:** local CRC (OpenShift 4.18.2) — a dev/test cluster.
**Date of run:** captured in this session.
**Short answer:** **No.** Kyverno is still needed to run our custom operator image.
`RELATED_IMAGE_MANAGER` does **not** change this operator's own image. The ZAP logging
env vars *do* work through OLM, and resource limits work too (with a caveat on CRC).

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
- Image override stays with Kyverno (or a future custom catalog).
