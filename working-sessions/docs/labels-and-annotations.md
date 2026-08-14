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

Extracted by rendering every `objectTemplate` — 11 of them across the 5 chart CRs — and cross-checked
against the 54 live objects the operator built from them (39 RoleBindings + 12 ClusterRoleBindings +
3 Roles). `custom` is included below; it did not exist when this table was first written.

| key | nonprod RB | prod RB | cluster CRB | custom CRB | oud-group Role | oud-group RB |
|---|---|---|---|---|---|---|
| **L** `app.kubernetes.io/managed-by` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `rbac.ocp.io/policy-version` | 0.1.0 | 0.1.0 | 0.1.0 | 0.1.0 | **—** | **—** |
| **L** `rbac.ocp.io/config-source` | nonprod-rbac | prod-rbac | cluster-rbac | custom-rbac | **—** | **—** |
| **L** `rbac.ocp.io/role-type` | ns-admin | ns-audit | cluster-admin | database-admin | **—** | **—** |
| **L** `rbac.ocp.io/access-level` | admin-non-prod-only | audit-prod-only | admin-cluster-wide | database-admin-cluster-wide | **—** | submitter |
| **L** `rbac.ocp.io/mnemonic` | beta | beta | — | — | — | — |
| **L** `rbac.ocp.io/environment` | rnd | prod | — | — | — | — |
| **L** `rbac.ocp.io/group-name` | — | — | app-ocp-rbac-… | app-ocp-rbac-… | — | — |
| **L** `rbac.ocp.io/custom-role` | — | — | — | database-admin | — | — |
| **L** `rbac.ocp.io/oud-group` | — | — | — | — | app-ocp-rbac-… | app-ocp-rbac-… |
| **L** `rbac.ocp.io/access-model` | — | — | — | — | oud-group-direct | oud-group-direct |
| **L** `rbac.ocp.io/rbac-type` | — | — | — | — | custom-role | — |
| **L** `rbac.ocp.io/source-namespaceconfig` | — | — | — | — | ✓ | ✓ |
| **A** `rbac.ocp.io/created-by` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **A** `rbac.ocp.io/source-namespaceconfig` | ✓ | ✓ | — | — | ✓ | ✓ |
| **A** `rbac.ocp.io/source-groupconfig` | — | — | ✓ | ✓ | — | — |
| **A** `rbac.ocp.io/source-namespace` | beta-rnd | beta-prod | — | — | ✓ | ✓ |
| **A** `rbac.ocp.io/group-name` | — | — | — | — | — | ✓ |
| **A** `rbac.ocp.io/group-pattern` | ✓ | ✓ | ✓ | ✓ | — | — |
| **A** `rbac.ocp.io/environment-restriction` | nonprod-only | prod-only | — | — | — | — |
| **A** `rbac.ocp.io/scope-restriction` | — | — | cluster-wide | cluster-wide | — | — |

`app.kubernetes.io/managed-by` is the only key on all 54 objects. Not every gap above is a defect —
`source-groupconfig` cannot appear on a NamespaceConfig's objects, and `mnemonic` / `environment` are
namespace-keyed by design. §2.1 separates the ones that are.

### 2.1 What the object-level inspection found, measured

**`rbac.ocp.io/access-level` does not mean the same thing in two families, and that breaks a query a
reviewer would actually run.** Its first component is the **bound ClusterRole** in the cluster and
custom families, but the **tier word** in nonprod and prod:

| family | `role-type` | `access-level` | actual `roleRef` | first component is |
|---|---|---|---|---|
| nonprod | ns-admin | admin-non-prod-only | admin | the roleRef *(coincidence — the words match)* |
| nonprod | ns-audit | **audit**-non-prod-only | **view** | the tier word |
| nonprod | ns-developer | **developer**-non-prod-only | **edit** | the tier word |
| prod | ns-audit | **audit**-prod-only | **view** | the tier word |
| prod | ns-developer | **developer**-prod-only | **edit** | the tier word |
| cluster | cluster-admin | admin-cluster-wide | admin | the roleRef |
| cluster | cluster-audit | **view**-cluster-wide | view | the roleRef |
| cluster | cluster-developer | **edit**-cluster-wide | edit | the roleRef |

So "who holds `view`?" answered via this label returns **2 of the 15 objects that actually bind
`ClusterRole/view`** — only the cluster-wide pair. The 13 namespace-scoped bindings grant the very same
`view` ClusterRole and are labelled `audit-*`:

```
objects binding ClusterRole/view    labelled access-level=view-*
  nonprod   10                        0
  prod       3                        0
  cluster    2                        2
  ------------------------------------------
  total     15                        2
```

A reviewer filtering `-l rbac.ocp.io/access-level=view-cluster-wide` sees 2 grants of `view` and misses
13. The scopes do differ — the 2 are cluster-wide, the 13 are per-namespace — so the label is not
lying about scope; it is inconsistent about **which ClusterRole**, and that is the axis someone asks
about when they ask who can read. **The most consequential finding here** — a wrong answer, not an
inconvenience.

And `role-type` already answers it correctly. Measured across all six tiers, the mapping is 1:1 with
no tier ever resolving to two roles:

```
role-type=cluster-admin      -> roleRef ['admin']      role-type=ns-admin      -> roleRef ['admin']
role-type=cluster-audit      -> roleRef ['view']       role-type=ns-audit      -> roleRef ['view']
role-type=cluster-developer  -> roleRef ['edit']       role-type=ns-developer  -> roleRef ['edit']
```

So §5's recommendation to drop `access-level` holds up under test: `role-type` + scope recover
everything it encodes, and unlike `access-level` they mean the same thing in every family. Dropping it
removes a key that gives a wrong answer rather than merely a redundant one.

**The same restriction is spelled two ways on one object.** `access-level: admin-non-prod-only`
alongside `environment-restriction: nonprod-only` — `non-prod-only` vs `nonprod-only`. Either spelling
is fine; both on the same object means neither can be matched reliably.

**Four keys carry a value that is already on the object under another key.** Verified on the live set:

| duplicate | measured |
|---|---|
| **A** `created-by` == **L** `managed-by` | both `namespace-configuration-operator`, all 54 objects |
| **A** `source-namespace` == `.metadata.namespace` | 30 of 30 nonprod RoleBindings |
| **L** `role-type` == **L** `custom-role` (custom only) | both `database-admin` |
| **L** `oud-group` == **A** `group-name` == `subjects[0].name` | all 3 oud-group RoleBindings |

**oud-group is the outlier on five keys, and `-l` queries silently return partial sets because of it:**

```
-l rbac.ocp.io/role-type                       48 of 54    (oud-group uses rbac-type, or nothing)
-l rbac.ocp.io/policy-version=0.1.0            48 of 54    (oud-group sets neither)
-l rbac.ocp.io/access-model                     6 of 54    (ONLY oud-group sets it at object level)
-l app.kubernetes.io/managed-by=…-operator     54 of 54    (the one key that answers completely)
```

It also spells the tier under `rbac-type: custom-role` where every other family uses `role-type` — two
keys four characters apart, holding different axes. And its RoleBinding sets **neither**, so the tier is
unqueryable there. `source-namespaceconfig` is a **label and an annotation** on its objects, which is
why `-l` on that key works for oud-group and nothing else (§3.1).

**Not a defect, though it looked like one:** `mnemonic` and `environment` are distinct facts, verified
`beta` / `rnd` on a live object. An earlier pass flagged them as duplicates — that was an artifact of
collapsing two different `index .Labels` expressions into one placeholder while rendering, not
something on the cluster. Rendered templates are evidence about the template; only the live object is
evidence about the object.

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

**GOTCHA 9 first blocked this, then a full rebuild closed it.** `.metadata` is in the `excludedPaths`
the operator injects, so the objectTemplate edit reached nothing that already existed. Measured
immediately after `helm upgrade` to rev 17:

```
$ oc get rolebinding,clusterrolebinding -A -l app.kubernetes.io/version=0.1.0 --no-headers | wc -l
48
```

The chart was correct and the cluster still wrong — exactly the two-generations state GOTCHA 9
predicts. It was resolved at rev 18 by deleting every NamespaceConfig and GroupConfig and letting the
operator rebuild from the chart, which is the only path that reaches existing objects:

```
$ oc get rolebinding,clusterrolebinding -A -l app.kubernetes.io/version=0.1.0 --no-headers | wc -l
0
$ oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/policy-version=0.1.0 --no-headers | wc -l
48        # of 51 — oud-group's 3 never set it, per §3.2
```

**The cost is a real revocation window, and it is the number to plan around, not the label change.**
Measured on this cluster across the delete/rebuild: **51 objects revoked in 4s**, all 51 restored
within 50s. Free on CRC; on a shared cluster that is ~50s during which every one of those grants is
absent. So a metadata realignment is a maintenance-window operation whose cost is set by the rebuild,
not by how many keys are changing — which is the argument for batching §6's remaining items into one
window rather than shipping them one at a time.

**And if you do it, select on `config-source`.** `oc -l` matches labels only, and the baseline and
cluster policies carry `rbac.ocp.io/source-namespaceconfig` / `source-groupconfig` as an
**annotation** — so a delete selecting on those keys matches nothing and reads as a clean no-op.
Measured per family:

```
-l rbac.ocp.io/source-namespaceconfig=nonprod-namespaceconfig-rbac    0  (of 30)
-l rbac.ocp.io/config-source=nonprod-rbac                           30
-l rbac.ocp.io/source-groupconfig=baseline-groupconfig-rbac           0  (of 12)
-l rbac.ocp.io/config-source=cluster-rbac                           12
-l rbac.ocp.io/source-namespaceconfig=oud-group-namespaceconfig-rbac  3  (of 3 — the exception)
```

This is §3.2's inconsistency biting: oud-group sets the key as a label and has no `config-source` at
all, so the ONE working selector differs by family. Four remediation commands in this repo were
written against the annotation and would have silently done nothing; corrected in the same change.

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

## 5. The aligned scheme — THE CONTRACT

Two rules decide everything below.

1. **One key, one fact.** No key encodes two axes, and no fact appears under two keys. A compound
   value is a value no selector can match on half of.
2. **Labels are for selecting; annotations are for reading.** If a reviewer would ever `-l` on it, it
   is a label. If it only explains, it is an annotation. Never both — that split is what made the
   remediation commands in §3.1 quietly select nothing.

A key is only worth adding if it answers a question someone actually asks. The four here are: *who is
this granting to*, *what does it grant*, *where does it apply*, and *which policy made it*.

### On generated objects — LABELS (selectable)

| key | values | on | change |
|---|---|---|---|
| `app.kubernetes.io/managed-by` | namespace-configuration-operator | all | unchanged |
| `rbac.ocp.io/config-source` | nonprod-rbac \| prod-rbac \| cluster-rbac \| custom-rbac \| oud-group-rbac | all | **add to oud-group** |
| `rbac.ocp.io/role-type` | ns-admin \| ns-developer \| ns-audit \| cluster-admin \| cluster-developer \| cluster-audit \| database-admin \| submitter | all | **add to oud-group**, retires `rbac-type` |
| `rbac.ocp.io/bound-role` | admin \| edit \| view \| database-admin \| oud-group-submitter-role | bindings | **NEW** — see below |
| `rbac.ocp.io/scope` | namespace-scoped \| cluster-wide | all | replaces both `*-restriction` annotations |
| `rbac.ocp.io/group-name` | the bound group | bindings | **add to nonprod/prod**, retires `oud-group` |
| `rbac.ocp.io/mnemonic`, `rbac.ocp.io/environment` | e.g. beta / rnd | namespace-keyed only | unchanged |

### On generated objects — ANNOTATIONS (explanatory)

| key | value | on | change |
|---|---|---|---|
| `rbac.ocp.io/source-namespaceconfig` \| `source-groupconfig` | the CR name | all | **annotation only** — drop oud-group's label copy |
| `rbac.ocp.io/group-pattern` | e.g. `app-ocp-rbac-*-cluster-admin` | pattern-derived families | unchanged; correctly absent on oud-group, whose group comes from a namespace label, not a pattern |

### Dropped from objects, with the reason each earns removal

| key | why it goes |
|---|---|
| `access-level` | §2.1 — means the roleRef in two families and the tier word in two others; answers "who has view" with 2 of 15. `role-type` + `bound-role` + `scope` replace it, each on one axis |
| `custom-role` | == `role-type` on the only family that sets it; `bound-role` now carries the role for every family |
| `rbac-type` | four characters from `role-type` and a different axis. The object's own `kind` already says Role vs RoleBinding |
| `policy-version` | §4 — never bumped, nothing enforces it, `helm.sh/chart` answers the question |
| `access-model` | 6 of 54 objects. Belongs on the CR (as `identity-source`), not repeated per object |
| `oud-group` | duplicate of `group-name`, which is now on everything |
| **A** `created-by` | byte-identical to `managed-by` on all 54 objects |
| **A** `source-namespace` | == `.metadata.namespace` on 30 of 30 checked |
| **A** `environment-restriction` | derivable from `config-source` — `nonprod-rbac` already says nonprod |
| **A** `scope-restriction` | == the new `scope` label, or `.metadata.namespace` for the namespaced case |
| **L** `source-namespaceconfig` | keeps its annotation form; the label copy existed only on oud-group and is what made `-l` behave differently per family |

**`bound-role` is an addition beyond what §5 originally proposed, and it is here to close the one
measured wrong answer.** Dropping `access-level` would otherwise remove the only place the actual
bound role was recorded, leaving `roleRef` reachable by `-o json` but not by `-l`. With it, the query
that returned 2 of 15 returns all 15:

```
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/bound-role=view
```

`role-type` and `bound-role` are deliberately both kept even though the mapping is 1:1 today: the tier
is the *promise* (`ns-audit`) and the role is the *implementation* (`view`). A future tier that binds a
different role breaks the mapping, and then the two keys are the only way to see it.

### On the CR

| key | value | change |
|---|---|---|
| Helm's five (`nco.labels`) | unchanged | already the only consistent block |
| `rbac.ocp.io/kind` | NamespaceConfig \| GroupConfig | unchanged |
| `rbac.ocp.io/scope` | namespace-scoped \| cluster-wide | **add to custom-gc**, which lacks it |
| `rbac.ocp.io/policy-family` | built-in \| custom | unchanged |
| `rbac.ocp.io/identity-source` | ldap-groups | renamed from `access-model`; one axis, true of all four |
| `rbac.ocp.io/group-naming` | pattern \| namespace-label | **NEW** — the axis `oud-group-direct` was really on |
| `app.kubernetes.io/component` | rbac-automation | **one value, not three** |
| ~~`policy-version`~~ | drop | §4 |
| ~~`app.kubernetes.io/part-of`~~ | drop | oud-group only; `policy-family` already groups the policies |
| ~~**A** `purpose`~~ | drop | oud-group only; folded into `description` |

§3.4 is what `identity-source` + `group-naming` fix: `access-model` was comparing where identities come
from (all four: LDAP) against how a group name is derived (pattern vs namespace label). Two axes, two
keys, and now `-l rbac.ocp.io/identity-source=ldap-groups` no longer under-reports.

### Migration cost

Because every policy excludes `.metadata`, changing labels on an `objectTemplate` reaches **nothing**
that already exists (GOTCHA 9). Realigning means deleting the objects so the operator rebuilds them —
and select on `config-source`, not on `source-*config`, per §3.1:

```sh
oc delete rolebinding -A -l rbac.ocp.io/config-source=nonprod-rbac
```

Measured across a whole-cluster rebuild: **51 objects revoked in 4s, all 51 restored within 50s.** Free
on CRC, a ~50s outage on a shared cluster. The cost is set by the rebuild, not by how many keys change,
so everything in this section should land in ONE window.

### 5.1 APPLIED — chart 0.8.0, verified on the cluster

Shipped in one window as argued above, and confirmed against the 55 live objects after the rebuild
(55 rather than 54 because the `-database-admin` group now exists, so `custom-groupconfig` produces its
first binding):

```
keys required on EVERY object
  app.kubernetes.io/managed-by      55/55      rbac.ocp.io/role-type    55/55
  rbac.ocp.io/config-source         55/55      rbac.ocp.io/scope        55/55
keys required on every BINDING (52 = 55 - the 3 Roles)
  rbac.ocp.io/bound-role            52/52      rbac.ocp.io/group-name   52/52

keys that had to be gone — all 0
  L access-level, custom-role, rbac-type, policy-version, access-model, oud-group
  A created-by, source-namespace, environment-restriction, scope-restriction

THE QUERY THAT USED TO RETURN 2 OF 15
  objects binding ClusterRole/view          15
  labelled rbac.ocp.io/bound-role=view      15
```

The object set is unchanged, which is the point — this was a metadata change, not a grant change:
12 cluster CRB + 1 custom CRB + 30 nonprod RB + 6 prod RB + 3 oud-group RB + 3 oud-group Role.

**One finding surfaced while implementing it, not present in the inventory above.**
`rbac.ocp.io/group-pattern` on the baseline NamespaceConfig objects was not a pattern at all — it held
a concrete group name, measured byte-identical to `subjects[0].name`:

```
group-pattern    : app-ocp-rbac-beta-ns-admin
subjects[0].name : app-ocp-rbac-beta-ns-admin      <- same value, so it was a NAME under a pattern key
```

On the GroupConfig policies the same key does hold a real wildcard
(`app-ocp-rbac-*-cluster-admin`). So the key meant two different things — the same failure mode as
`access-level`, found in a key nobody had flagged. It is now dropped from the namespace policies, where
the value it carried is the `group-name` label instead, and kept on the two GroupConfig policies where
it is genuinely a pattern.

---

## 6. What I would do, in order

1. ~~**Fix `app.kubernetes.io/version` on objects**~~ — **DONE**, and done FIRST rather than second.
   The original ordering had it following (2) on the reasoning that "that label only carried the policy
   version", which implied the two had to move together. They do not: this one is the §3.1 *defect* —
   a well-known key given a second, contradictory meaning — while (2) is a *preference* about whether
   a version constant is worth carrying at all. Separating them let the defect ship on its own, with
   `rbac.ocp.io/policy-version` left untouched so nothing became unqueryable. See §3.1 for the
   verification and for why the 48 existing objects still read `0.1.0`.
2. ~~**Drop `policyVersion`**~~ (§4) — **DONE**. Gone from all four values stanzas and both label sites.
3. ~~**Add the three missing keys**~~ — **DONE**. `scope` on custom-gc's CR, `config-source` +
   `role-type` on oud-group's objects.
4. ~~**Unify `group-name`**~~ — **DONE**. `rbac.ocp.io/oud-group` retired; `group-name` is on all 52
   bindings, and was also added to nonprod/prod, which never had it.
5. ~~**Collapse the `*-restriction` annotations, simplify `access-level`**~~ — **DONE**, and it went
   further than "simplify": `access-level` is removed outright, because §2.1 showed it answers a real
   question wrongly rather than just awkwardly. `role-type` + `bound-role` + `scope` replace it.
6. ~~**Rename `access-model`**~~ — **DONE**. Split into `identity-source` (all four: ldap-groups) and
   `group-naming` (pattern vs namespace-label), which is what §3.4 said it was conflating.

**ALL SIX ARE APPLIED, in chart 0.8.0, and live on the cluster** — items 2–6 shipped together in one
rebuild window exactly as the cost analysis argued, since the window is priced by the rebuild rather
than by the number of keys. §5.1 has the verification against all 55 objects.

§§1–4 are left as written: they are the evidence that motivated the change, and rewriting them into
the past tense would delete the reasoning while keeping only the conclusion. §5 is the contract as it
now stands; §5.1 is proof the cluster matches it.

**Two things this did NOT do**, and both are deliberate rather than forgotten:

- **The source policies under `working-sessions/policies/` are untouched.** They remain the readable
  reference for what was originally hand-applied, and they still carry the old keys. They now diverge
  from the chart on labels as well as on structure — which is the same call §3.1 made for
  `app.kubernetes.io/version`: the source is the record, not the target.
- **`rbac.ocp.io/policy-family` is still CR-only, not on objects.** It would be a seventh key on all 55
  and it is derivable from `config-source` (`cluster-rbac` and `nonprod-rbac` are built-in;
  `custom-rbac` and `oud-group-rbac` are not). Rule 1 of the contract says one key per fact, and this
  fact already has one.
