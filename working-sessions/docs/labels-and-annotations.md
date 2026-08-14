# Labels and annotations across the RBAC policies

Extracted from the live CRC cluster at `nco` revision 16, chart 0.7.0 — five Helm-owned policies and
the 54 objects they create. Not from reading the templates: from `oc get -o json` on what actually
exists, because the templates and the cluster have disagreed before.

**The short version:** there are 21 distinct keys in play, and they are not applied consistently. Four
concrete problems, one of which is a real defect. And `policy-version` earns its own section, because
the answer to "do we need it?" is **no** — with evidence.

---

## 1. CR-level: the five policies

| key | built-in ns<br/>(nonprod, prod) | built-in cluster<br/>(baseline-gc) | custom ns<br/>(oud-group) | custom cluster<br/>(custom-gc) |
|---|---|---|---|---|
| **L** `app.kubernetes.io/name` | ✓ | ✓ | ✓ | ✓ |
| **L** `app.kubernetes.io/instance` | ✓ | ✓ | ✓ | ✓ |
| **L** `app.kubernetes.io/managed-by` | Helm | Helm | Helm | Helm |
| **L** `app.kubernetes.io/version` | 1.2.6 | 1.2.6 | 1.2.6 | 1.2.6 |
| **L** `helm.sh/chart` | ✓ | ✓ | ✓ | ✓ |
| **L** `app.kubernetes.io/component` | `rbac-automation` | `cluster-rbac-automation` | `rbac-automation` | `custom-rbac-automation` |
| **L** `app.kubernetes.io/part-of` | — | — | `oud-group` | — |
| **L** `rbac.ocp.io/kind` | NamespaceConfig | GroupConfig | NamespaceConfig | GroupConfig |
| **L** `rbac.ocp.io/scope` | namespace-scoped | cluster-wide | namespace-scoped | **—** |
| **L** `rbac.ocp.io/policy-family` | built-in | built-in | custom | custom |
| **L** `rbac.ocp.io/access-model` | ldap-groups | ldap-groups | **oud-group-direct** | ldap-groups |
| **L** `rbac.ocp.io/policy-version` | 0.1.0 | 0.1.0 | 0.1.0 | 0.1.0 |
| **A** `description` | ✓ | ✓ | ✓ | ✓ |
| **A** `argocd.argoproj.io/sync-wave` | 3 | 3 | 3 | 3 |
| **A** `rbac.ocp.io/purpose` | — | — | ✓ | — |

The first five are Helm's, from `_helpers.tpl#nco.labels`, and they are the only fully consistent
block. Everything below them varies.

## 2. Object-level: what the policies create

| key | nonprod RB | prod RB | cluster CRB | oud-group Role | oud-group RB |
|---|---|---|---|---|---|
| **L** `app.kubernetes.io/managed-by` | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `app.kubernetes.io/version` | 0.1.0 | 0.1.0 | 0.1.0 | **—** | **—** |
| **L** `rbac.ocp.io/policy-version` | 0.1.0 | 0.1.0 | 0.1.0 | **—** | **—** |
| **L** `rbac.ocp.io/config-source` | nonprod-rbac | prod-rbac | cluster-rbac | **—** | **—** |
| **L** `rbac.ocp.io/role-type` | ns-admin | ns-audit | cluster-admin | **—** | **—** |
| **L** `rbac.ocp.io/access-level` | admin-non-prod-only | audit-prod-only | admin-cluster-wide | **—** | submitter |
| **L** `rbac.ocp.io/mnemonic` | beta | beta | — | — | — |
| **L** `rbac.ocp.io/environment` | rnd | prod | — | — | — |
| **L** `rbac.ocp.io/group-name` | — | — | app-ocp-rbac-… | — | — |
| **L** `rbac.ocp.io/oud-group` | — | — | — | app-ocp-rbac-… | app-ocp-rbac-… |
| **L** `rbac.ocp.io/access-model` | — | — | — | oud-group-direct | oud-group-direct |
| **L** `rbac.ocp.io/rbac-type` | — | — | — | custom-role | — |
| **L** `rbac.ocp.io/source-namespaceconfig` | — | — | — | ✓ | ✓ |
| **A** `rbac.ocp.io/created-by` | ✓ | ✓ | ✓ | ✓ | ✓ |
| **A** `rbac.ocp.io/source-namespaceconfig` | ✓ | ✓ | — | ✓ | ✓ |
| **A** `rbac.ocp.io/source-groupconfig` | — | — | ✓ | — | — |
| **A** `rbac.ocp.io/source-namespace` | beta-rnd | beta-prod | — | ✓ | ✓ |
| **A** `rbac.ocp.io/group-name` | — | — | — | — | ✓ |
| **A** `rbac.ocp.io/group-pattern` | ✓ | ✓ | ✓ | — | — |
| **A** `rbac.ocp.io/environment-restriction` | nonprod-only | prod-only | — | — | — |
| **A** `rbac.ocp.io/scope-restriction` | — | — | cluster-wide | — | — |

---

## 3. The four problems

### 3.1 A DEFECT: `app.kubernetes.io/version` means two different things — FIXED IN THE CHART

```
on a CR              app.kubernetes.io/version: 1.2.6    <- appVersion, the OPERATOR version
on its objects       app.kubernetes.io/version: 0.1.0    <- policyVersion, the POLICY version
```

Same well-known key, two meanings, one policy. A reader filtering
`-l app.kubernetes.io/version=1.2.6` gets the CRs and none of the objects; filtering `0.1.0` gets the
reverse. This is the only item here I would call a bug rather than an inconsistency — the key is part
of the Kubernetes recommended-labels set with a defined meaning, and the object-level use contradicts
it.

**RESOLVED.** The hand-set line is gone from all three objectTemplates; the key is now written in
exactly one place, `_helpers.tpl#nco.labels`, from `Chart.AppVersion`, and lands on the CR only. The
version of the policy was never carried solely by this key — `rbac.ocp.io/policy-version: 0.1.0` is
still on every generated object — so nothing became unqueryable:

```
$ helm template … | (per CR)
  baseline-groupconfig-rbac       CR=1.2.6   objects mentioning app.kubernetes.io/version: none
  custom-groupconfig-rbac         CR=1.2.6   objects mentioning app.kubernetes.io/version: none
  nonprod-namespaceconfig-rbac    CR=1.2.6   objects mentioning app.kubernetes.io/version: none
  prod-namespaceconfig-rbac       CR=1.2.6   objects mentioning app.kubernetes.io/version: none
  oud-group-namespaceconfig-rbac  CR=1.2.6   objects mentioning app.kubernetes.io/version: none
```

This DIVERGES from the source policies under `working-sessions/policies/`, which do set it on their
objects. Deliberate: the source is what had the defect.

**The 48 objects already on the cluster keep the stale `0.1.0` — GOTCHA 9.** `.metadata` is in the
`excludedPaths` the operator injects, so an objectTemplate metadata edit never reaches an object that
already exists. Measured after `helm upgrade` to rev 17:

```
$ oc get rolebinding,clusterrolebinding -A -l app.kubernetes.io/version=0.1.0 --no-headers | wc -l
48
```

Making it retroactive means `oc delete` by `rbac.ocp.io/source-*config` and letting the operator
rebuild — a real revocation window (measured elsewhere in this repo: 2s to revoke, ~40s to restore).
Whether a cosmetic label correction is worth that window is a judgement call, not a cleanup step, so
it is deliberately not done here.

### 3.2 The same fact carried under different keys, and different kinds

| the fact | built-in policies | oud-group |
|---|---|---|
| which group is bound | `rbac.ocp.io/group-name` (label, cluster only) | `rbac.ocp.io/oud-group` (label) + `rbac.ocp.io/group-name` (annotation) |
| which CR created this | `source-namespaceconfig` / `source-groupconfig` (annotation) | both a **label** and an annotation |
| the tier | `role-type` | absent |
| the policy | `config-source` | absent |

Two keys for "the bound group" is the worst of these: neither `oc get -l rbac.ocp.io/group-name=X` nor
`-l rbac.ocp.io/oud-group=X` finds everything bound to a group.

### 3.3 Overlapping encodings of the same restriction

```
nonprod RB:   access-level: admin-non-prod-only     +  environment-restriction: nonprod-only
cluster CRB:  access-level: admin-cluster-wide      +  scope-restriction: cluster-wide
```

The label already contains what the annotation says. And `access-level` is doing two jobs at once —
tier *and* restriction — which is why its values are compound strings that no selector can usefully
match on. `-l rbac.ocp.io/access-level=admin` matches nothing; you need the whole
`admin-non-prod-only`.

### 3.4 `access-model` compares different axes

```
built-in policies:  ldap-groups        <- where the IDENTITIES come from
oud-group:          oud-group-direct   <- how the group NAME is derived
```

Both facts are true and worth recording; they are not the same axis. oud-group is *also* LDAP-backed,
so `-l rbac.ocp.io/access-model=ldap-groups` under-reports. (I introduced `ldap-groups` while
oud-group already had `oud-group-direct` — this one is mine.)

---

## 4. `policy-version`: no, we do not need it

Carried over from the Kyverno work, where a policy is a standalone object with its own lifecycle. Here
it is not, and the evidence is against it:

1. **It has never moved.** All four occurrences in `values.yaml` read `0.1.0`, and every commit
   touching `policyVersion` is the commit that *introduced* it for a new stanza. Never once bumped —
   across four policies and seven chart versions.

   And it is not a maintained convention outside the chart either. The three hand-applied policies on
   this cluster disagree with each other:

   ```
   bda-workload-submitter-namespaceconfig-rbac   policy-version=1.0.0
   multitenant                                    (absent)
   database-admin-groupconfig-rbac                (absent)
   ```

   One at `1.0.0`, two with no label at all. So a reader who checks the cluster finds three different
   answers to "is this label maintained?" — which is the strongest evidence that it is not.
2. **Nothing enforces it.** There is no test, no CI check, and no render guard tying it to anything —
   unlike `Chart.yaml`'s version, which `ci.yaml` will refuse a chart change without.
3. **It duplicates a label that already exists**, and does so incorrectly — see 3.1. On the objects it
   is stamped twice, as `policy-version` and as `app.kubernetes.io/version`, with the same value.
4. **Three version axes already exist, and one of them answers the question.**

   | axis | value | moves? |
   |---|---|---|
   | `Chart.yaml` `version` | 0.7.0 | **yes** — every policy change, and CI can enforce it |
   | `Chart.yaml` `appVersion` | 1.2.6 | with the operator |
   | `rbac.ocp.io/policy-version` | 0.1.0 | never |

   "Which revision of this policy is the cluster running?" is answered by `helm.sh/chart`, which is on
   every CR already and *does* move: `namespace-configuration-operator-0.7.0`. Plus `helm history nco`
   for the full record.

**Recommendation: drop `policyVersion` from values and from both label sites.** It costs four values
keys, eight template lines, and one wrong `app.kubernetes.io/version`, and it buys a constant.

If a per-policy version is genuinely wanted later, it needs the thing it lacks now: a rule that bumps
it and a check that enforces it. Without that it is decoration that looks like provenance — which is
worse than absent, because someone will trust it.

---

## 5. A proposed aligned scheme

Same keys on every policy and every object, each carrying exactly one fact.

### On the CR

| key | value | why |
|---|---|---|
| Helm's five (`nco.labels`) | unchanged | ownership and chart provenance, already consistent |
| `rbac.ocp.io/kind` | NamespaceConfig \| GroupConfig | what triggers it |
| `rbac.ocp.io/scope` | namespace-scoped \| cluster-wide | **add to custom-gc, which is missing it** |
| `rbac.ocp.io/policy-family` | built-in \| custom | where the bound roles come from |
| `rbac.ocp.io/identity-source` | ldap-groups | renamed from `access-model`; one axis, true of all four |
| `rbac.ocp.io/group-naming` | pattern \| label-value | the axis `oud-group-direct` was really on |
| `app.kubernetes.io/component` | `rbac-automation` | **one value, not three** |
| ~~`rbac.ocp.io/policy-version`~~ | drop | §4 |
| ~~`app.kubernetes.io/part-of`~~ | drop, or set on all four | currently oud-group only |

### On generated objects

| key | value | why |
|---|---|---|
| `app.kubernetes.io/managed-by` | namespace-configuration-operator | who created it |
| `rbac.ocp.io/config-source` | the policy's short name | **add to oud-group's objects** |
| `rbac.ocp.io/group-name` | the bound group | **one key for this, everywhere** — retires `oud-group` |
| `rbac.ocp.io/role-type` | ns-admin \| cluster-audit \| submitter … | the tier, alone |
| `rbac.ocp.io/scope` | namespace-scoped \| cluster-wide | replaces the two `*-restriction` annotations |
| `rbac.ocp.io/mnemonic`, `environment` | as now | namespace-keyed policies only, which is correct |
| ~~`access-level`~~ | drop | compound; `role-type` + `scope` carry it selectably |
| ~~`app.kubernetes.io/version`~~ | **DROPPED — done** | §3.1 — it is the wrong key for a policy version |
| **A** `source-namespaceconfig` / `source-groupconfig` | as now | annotation, not label — it is provenance, not a selector |

**Migration cost is not zero, and this is the part to weigh.** Because every policy excludes
`.metadata`, changing labels on an `objectTemplate` does **not** reach objects that already exist
(GOTCHA 9). Realigning means deleting the generated objects so the operator rebuilds them:

```sh
oc delete rolebinding -A -l rbac.ocp.io/config-source=nonprod-rbac
```

Measured on this cluster: a full delete-and-rebuild of one policy's objects is 2s to revoke and ~40s
to restore. That is a **real revocation window** on 54 objects — free on CRC, an outage on a shared
cluster. So this is a maintenance-window change, not a drive-by.

---

## 6. What I would do, in order

1. ~~**Fix `app.kubernetes.io/version` on objects**~~ — **DONE**, and done FIRST rather than second.
   The original ordering had it following (2) on the reasoning that "that label only carried the policy
   version", which implied the two had to move together. They do not: this one is the §3.1 *defect* —
   a well-known key given a second, contradictory meaning — while (2) is a *preference* about whether
   a version constant is worth carrying at all. Separating them let the defect ship on its own, with
   `rbac.ocp.io/policy-version` left untouched so nothing became unqueryable. See §3.1 for the
   verification and for why the 48 existing objects still read `0.1.0`.
2. **Drop `policyVersion`** (§4). Removes a constant and four values keys. Still open, and now purely
   a question of whether the constant earns its keep — no longer entangled with (1).
3. **Add the three missing keys**: `rbac.ocp.io/scope` on custom-gc's CR, and `config-source` +
   `role-type` on oud-group's objects. Additive, no removals.
4. **Unify `group-name`** — retire `rbac.ocp.io/oud-group`. One key for "which group is bound".
5. **Collapse the `*-restriction` annotations into `rbac.ocp.io/scope`** and simplify `access-level`.
   The largest change and the one that most needs a window.
6. **Rename `access-model`** to split its two axes, or leave it and document that it means two things.

2–3 can ship together with no object churn. 4–6 need the maintenance window.

**Applied so far: (1) only.** The rest of this document is the inventory and the argument; those
changes remain separate decisions. Note that (1) shipped in the chart but is NOT retroactive on the
cluster — §3.1 explains why, and that gap is itself a decision left open rather than an oversight.
