# Labels and annotations — the contract

The canonical definition of every label and annotation this project sets, on the policy CRs and on the
objects they create. Chart 0.8.0. Every value below was taken from `oc get -o json` against the running
cluster — 5 CRs and the 55 objects they created — not from reading the templates.

If you are adding a policy or a key, this file is the spec. If a key is not here, we do not set it.

---

## The two rules

**1. One key, one fact.** No key encodes two axes, and no fact appears under two keys. A compound value
is a value no selector can match half of.

**2. Labels are for selecting; annotations are for reading.** If someone would ever `oc get -l` on it,
it is a label. If it only explains, it is an annotation. **Never both** — `oc -l` matches labels only,
so a key that is an annotation on one policy and a label on another makes the same query behave
differently per policy, and it fails *silently*.

A key earns its place only if it answers a question someone actually asks. Those questions are: **who is
this granting to**, **what does it grant**, **where does it apply**, and **which policy made it**.

---

## 1. On generated objects — LABELS

Set inside each `objectTemplate`, so the operator writes them onto every RoleBinding, ClusterRoleBinding
and Role it creates.

| key | values on the cluster today | meaning |
|---|---|---|
| `app.kubernetes.io/managed-by` | `namespace-configuration-operator` | the operator created this; hand-made RBAC has no such label |
| `rbac.ocp.io/config-source` | `nonprod-rbac` `prod-rbac` `cluster-rbac` `custom-rbac` `oud-group-rbac` | which policy produced it — **the selector to use for a delete-and-rebuild** |
| `rbac.ocp.io/role-type` | `ns-admin` `ns-developer` `ns-audit` `cluster-admin` `cluster-developer` `cluster-audit` `database-admin` `submitter` | the **tier** — the promise being made |
| `rbac.ocp.io/bound-role` | `admin` `edit` `view` `database-admin` `oud-group-submitter-role` | the role **actually referenced** by `roleRef` — the effective permission |
| `rbac.ocp.io/scope` | `namespace-scoped` `cluster-wide` | whether it applies in one namespace or all of them |
| `rbac.ocp.io/group-name` | e.g. `app-ocp-rbac-beta-ns-admin` | the Group in `subjects` — one key for this on every policy |
| `rbac.ocp.io/mnemonic` | e.g. `beta` `demo` `jeff` | the team, from the namespace label — **namespace-keyed policies only** |
| `rbac.ocp.io/environment` | `rnd` `qa` `uat` `prod` | the environment, from the namespace label — **namespace-keyed policies only** |

### Why `role-type` and `bound-role` are both kept

The mapping is 1:1 today, verified across all six baseline tiers:

```
role-type=cluster-admin      → bound-role=admin      role-type=ns-admin      → bound-role=admin
role-type=cluster-audit      → bound-role=view       role-type=ns-audit      → bound-role=view
role-type=cluster-developer  → bound-role=edit       role-type=ns-developer  → bound-role=edit
```

They are still two keys because they are two facts: the tier is the **promise** (`ns-audit`), the role is
the **implementation** (`view`). Note the tier names deliberately do not match the roles — `audit` binds
`view`, `developer` binds `edit`. A future tier that binds a different role breaks the 1:1, and then
these are the only two keys that can show it.

`bound-role` is also what makes the effective-permission question answerable:

```sh
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/bound-role=view    # all 15
```

---

## 2. On generated objects — ANNOTATIONS

| key | values | meaning |
|---|---|---|
| `rbac.ocp.io/source-namespaceconfig` | `nonprod-namespaceconfig-rbac` `prod-namespaceconfig-rbac` `abc-oud-group-namespaceconfig-rbac` | the NamespaceConfig that owns it |
| `rbac.ocp.io/source-groupconfig` | `baseline-cluster-groupconfig-rbac` `custom-groupconfig-rbac` | the GroupConfig that owns it |
| `rbac.ocp.io/group-pattern` | `app-ocp-rbac-*-cluster-admin`, `app-ocp-rbac-*-database-admin`, … | the wildcard the operator matched groups against |

**These are annotations on purpose, and `oc -l` will not find them.** Provenance is for reading, and
`config-source` is the label that answers the same question selectably. Use it for any bulk operation:

```sh
oc delete rolebinding -A -l rbac.ocp.io/config-source=nonprod-rbac      # 30 objects
oc delete clusterrolebinding  -l rbac.ocp.io/config-source=cluster-rbac # 12 objects
```

`group-pattern` appears only where the value genuinely **is** a pattern — the two GroupConfig policies.
The namespace-keyed policies compute a concrete group name instead, and that name is the `group-name`
label, where it can be selected on.

---

## 3. On the policy CRs

| key | values | meaning |
|---|---|---|
| `helm.sh/chart` | `namespace-configuration-operator-0.8.0` | **which revision of the policies a cluster is running** — this moves, so it is the version answer |
| `app.kubernetes.io/name` | `namespace-configuration-operator` | Helm, from `_helpers.tpl#nco.labels` |
| `app.kubernetes.io/instance` | `nco` | the Helm release |
| `app.kubernetes.io/managed-by` | `Helm` | note: **`Helm` on a CR, the operator on an object** — that is how you tell the two layers apart |
| `app.kubernetes.io/version` | `1.2.6` | the **operator** version, from `Chart.AppVersion`. Set in exactly one place, and never on an object |
| `app.kubernetes.io/component` | `rbac-automation` | one value across all policies, so one query finds the whole set |
| `rbac.ocp.io/kind` | `NamespaceConfig` `GroupConfig` | what the policy is keyed on |
| `rbac.ocp.io/scope` | `namespace-scoped` `cluster-wide` | the CR-level worst case; individual entries may be narrower |
| `rbac.ocp.io/policy-family` | `built-in` `custom` | `built-in` binds OpenShift's aggregated roles, whose contents are Red Hat's and move with the release; `custom` binds roles we define |
| `rbac.ocp.io/identity-source` | `ldap-groups` | where the identities come from — true of all policies, and the reason editing a binding by hand is pointless |
| `rbac.ocp.io/group-naming` | `pattern` `namespace-label` | how the group name is derived: computed from a convention, or read verbatim from a namespace label |

**Annotations on the CR:** `description` (one line, on every policy) and
`argocd.argoproj.io/sync-wave: "3"` (after the operator and its CRDs).

`identity-source` and `group-naming` are separate because they are different axes. Every policy is
LDAP-backed; they do not all name groups the same way. One key covering both would under-report.

---

## 4. Which keys appear where, and why the gaps are correct

| key | nonprod RB | prod RB | cluster CRB | custom CRB | oud-group RB | oud-group Role |
|---|---|---|---|---|---|---|
| **L** `managed-by` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `config-source` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `role-type` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `scope` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **L** `bound-role` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| **L** `group-name` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| **L** `mnemonic`, `environment` | ✓ | ✓ | — | — | — | — |
| **A** `source-namespaceconfig` | ✓ | ✓ | — | — | ✓ | ✓ |
| **A** `source-groupconfig` | — | — | ✓ | ✓ | — | — |
| **A** `group-pattern` | — | — | ✓ | ✓ | — | — |

Four keys are on all 55 objects; `bound-role` and `group-name` are on all 52 bindings. Every remaining
gap is structural, not an oversight:

- **The Role has no `bound-role` or `group-name`.** It *is* the role rather than referencing one, and it
  is created once per **namespace** with a fixed name, not once per group — so naming a single group on
  it would be wrong, not merely redundant.
- **`mnemonic` / `environment` only on namespace-keyed policies.** A ClusterRoleBinding is not in a
  namespace, so there is no namespace label to read.
- **`source-namespaceconfig` vs `source-groupconfig`** mirrors which CRD created the object. A
  GroupConfig cannot set the other.
- **`group-pattern` only where a pattern exists.** oud-group reads its group from a namespace label;
  there is no wildcard to record.

---

## 4a. What this contract does NOT cover

Three classes of object are deliberately outside it, so that "align everything" does not become
"flatten different things into one vocabulary".

**Kyverno `ClusterPolicy` objects** (`working-sessions/policies/kyverno-*.yaml`). They are validation
policies, not RBAC grants. Their own labels — `rbac.ocp.io/group-family`, `rbac.ocp.io/exempt`,
`rbac.ocp.io/test-fixture`, `app.kubernetes.io/part-of` — describe a Kyverno policy, and nothing in §1–3
applies. Left as they are.

**Hand-applied supporting objects**, such as `working-sessions/policies/database-admin-clusterrole.yaml`.
A ClusterRole the chart binds but does not create is neither a policy CR nor an operator-generated
object. It carries `rbac.ocp.io/policy-family` so it is findable next to the policy that binds it, and
`rbac.ocp.io/bound-by` as an **annotation** — provenance, not a selector. It does **not** carry
`config-source`, `role-type` or the rest, because no policy generated it.

**Per-family extension labels** on policies that need an axis the contract has no key for.
`working-sessions/policies/bda-namespace-config.yaml` sets `rbac.ocp.io/bda-team` and its sibling sets
`rbac.ocp.io/bdp-spark-team` — a second team axis alongside `mnemonic`, read from a namespace label.
These are allowed, and the bar is: it must be a fact no existing key holds, and it must be named for the
family that needs it. Reaching for an extension because an existing key is *nearly* right is how the old
overlap happened — check §1 first.

---

## 5. Query cookbook

What each key is *for*, as commands. `-A` on namespaced kinds; ClusterRoleBindings are not namespaced.

```sh
# Everything this automation created — the only fully complete answer
oc get rolebinding,clusterrolebinding,role -A \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator

# EFFECTIVE PERMISSION: who can read, anywhere, regardless of tier naming
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/bound-role=view

# Everything one policy produced — use this for delete-and-rebuild
oc get rolebinding -A -l rbac.ocp.io/config-source=nonprod-rbac

# Everything granted to one group, across all policies
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/group-name=app-ocp-rbac-beta-ns-admin

# Every cluster-wide grant — the blast-radius question
oc get clusterrolebinding -l rbac.ocp.io/scope=cluster-wide

# One tier across both scopes
oc get rolebinding,clusterrolebinding -A -l 'rbac.ocp.io/role-type in (ns-audit,cluster-audit)'

# One team's namespace grants
oc get rolebinding -A -l rbac.ocp.io/mnemonic=beta

# Production grants only
oc get rolebinding -A -l rbac.ocp.io/environment=prod

# Grants of roles we define, as against OpenShift's built-ins
oc get namespaceconfig,groupconfig -l rbac.ocp.io/policy-family=custom

# Which policy revision is deployed
oc get namespaceconfig,groupconfig -L helm.sh/chart
```

**Two things `-l` cannot do**, so do not build a process on them:

- **Annotations.** `-l rbac.ocp.io/source-groupconfig=…` matches **nothing**. Use `config-source`.
- **`roleRef` and `subjects`.** They are spec fields, not metadata. `bound-role` and `group-name` exist
  precisely so those two facts are reachable by selector.

---

## 6. Changing a label

**An `objectTemplate` metadata change does not reach objects that already exist.** The operator injects
`excludedPaths: [.metadata, .status, .spec.replicas]` on reconcile, so `.metadata` is excluded from
comparison. `helm upgrade` reports success, the CR is correct, and every existing object keeps its old
labels — a cluster with two generations of metadata and nothing complaining. (This is GOTCHA 9 in
`working-sessions/README.md`.) Spec-level changes — `subjects`, `roleRef`, `rules` — **do** propagate.

The only way to move metadata onto existing objects is to delete them and let the operator rebuild:

```sh
oc delete namespaceconfig --all && oc delete groupconfig --all
helm upgrade nco charts/namespace-configuration-operator -n namespace-configuration-operator …   # recreates the CRs
```

**Measured cost, whole cluster:** 55 objects revoked in ~4s, all restored within ~50s. Free on CRC; on a
shared cluster that is ~50s during which every one of those grants is **absent**. The cost is set by the
rebuild, not by how many keys change — so batch label work into one window rather than shipping keys one
at a time.

Deleting a NamespaceConfig or GroupConfig **revokes what it created**, via the operator's finalizers. It
is not ownerReferences and not Kubernetes GC. Never delete one casually to "clean up".

---

## 7. Adding a policy — the checklist

1. **Labels:** set all four universal keys (`managed-by`, `config-source`, `role-type`, `scope`), plus
   `bound-role` and `group-name` on anything with a `roleRef` and `subjects`.
2. **A new `config-source` value**, short and distinct. It is the selector everything else relies on.
3. **Annotations:** the matching `source-namespaceconfig` / `source-groupconfig`. Add `group-pattern`
   only if the group really is matched by a wildcard.
4. **On the CR:** `rbac.ocp.io/kind`, `scope`, `policy-family`, `identity-source`, `group-naming`,
   `component: rbac-automation`, a `description`, and the shared Helm block via
   `include "nco.labels"`.
5. **Do not invent a key** for something an existing key already carries, and do not set the same fact
   as both a label and an annotation.
6. **Never set `app.kubernetes.io/version` on an object.** It is Helm's key with a defined meaning — the
   application version — and `_helpers.tpl#nco.labels` already sets it on the CR. Provenance belongs in
   `source-*config`, which points at the CR and cannot go stale the way a copied version string does.
7. **Verify by rendering then parsing**, never by reading the template — see
   `working-sessions/docs/templating-guide.md` §5.

### Constraints the API enforces

- A label **value** is ≤63 characters, and must start and end alphanumeric. `_helpers.tpl` handles this
  for `helm.sh/chart` with `trunc 63 | trimSuffix "-"`. Long group names are the realistic risk here:
  `app-ocp-rbac-alpha-database-admin` is 33 characters, so there is headroom, but a much longer
  mnemonic plus a long custom suffix could exceed it and the API would reject the object.
- An **annotation** value has no such limit, which is another reason provenance lives there.
- Both keys and values are case-sensitive. `scope: cluster-wide` and `Cluster-Wide` are different
  values; the templates guard the ones that come from values.

---

## See also

- `working-sessions/docs/templating-guide.md` — how the templates compute these values, `$group`, and
  the Helm functions involved
- `working-sessions/README.md` — GOTCHA 9 and the operator's behaviour in general
- `working-sessions/policies/` — the reference manifests, aligned to this contract. Verified: every
  `objectTemplate` across the 10 RBAC policies there renders to valid YAML and sets **only** keys from
  §1–2 (plus the §4a family extensions). The Kyverno policies in the same directory are out of scope per
  §4a.
- `charts/namespace-configuration-operator/templates/rbac-policies/_README.txt` — the four deployable policies and the rules for adding one

**The history behind this contract is in git, not here.** The measurements that justified each choice —
which keys were duplicates, which answered a question wrongly, and what the queries returned before and
after — are in the commit messages, principally `6f5ed3b` (the alignment) and the commits that preceded
it. This file is deliberately the current state only; carrying the retired vocabulary alongside it is
what makes a reference ambiguous.
