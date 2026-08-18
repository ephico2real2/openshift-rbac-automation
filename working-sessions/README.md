# BDA RBAC — working session

End-to-end walkthrough on the local CRC cluster: create namespaces, watch the standard RBAC
fail silently, fix it by seeding LDAP, then layer the BDA workload-submitter policy on top.

Everything below was executed and the output is real, not illustrative.

## Files

| File | Purpose |
|---|---|
| `bda-namespace.yaml` | Three sample namespaces (`spar-rnd`, `spar-qa`, `trno-uat`) |
| `bda-namespace-config.yaml` | The BDA `NamespaceConfig` — binds `bda-rbac-*` groups |
| `bdp-namespace-config.yaml` | Original spark draft, superseded — see "Why it was replaced" |
| `verify-bda-rolebindings.sh` | Resolves every BDA RoleBinding to its real group membership — see "Verifying" |
| `kyverno-label-test-namespaces.yaml` | 8 namespaces exercising every namespace-label rule, pass and fail |
| `verify-kyverno-label-tests.sh` | Asserts Kyverno's verdicts match the declared expectations; exits non-zero on drift |
| `oud-group-namespaceconfig.yaml` | PoC: label names the group directly, no prefix added by the template |
| `oud-group-namespace.yaml` | PoC namespaces for the oud-group design |
| `../../group-sync-operator-helm-chart/setup-local-ldap-testing/ldap-rbac-groups-spar-trno.ldif` | LDAP seed for the `spar` / `trno` mnemonics |

## The headline result

**A NamespaceConfig creates its RoleBindings whether or not the groups exist.** The
"failure" is invisible: the objects look perfectly healthy and grant nobody.

---

## Step 1 — create the namespaces

```bash
oc apply -f working-sessions/bda-namespace.yaml
```

The standard `nonprod-namespaceconfig-rbac` matched immediately (all three namespaces carry
`company.net/mnemonic` + a non-prod `app-environment`) and created **all three** RoleBindings:

```
spar-rnd
  spar-admin-rb        ClusterRole/admin   Group:app-ocp-rbac-spar-ns-admin
  spar-audit-rb        ClusterRole/view    Group:app-ocp-rbac-spar-ns-audit
  spar-developer-rb    ClusterRole/edit    Group:app-ocp-rbac-spar-ns-developer
```

Every one of those groups was **missing**:

```
MISSING app-ocp-rbac-spar-ns-admin
MISSING app-ocp-rbac-spar-ns-developer
MISSING app-ocp-rbac-spar-ns-audit
MISSING app-ocp-rbac-trno-ns-admin
MISSING app-ocp-rbac-trno-ns-developer
MISSING app-ocp-rbac-trno-ns-audit
```

> ### GOTCHA 1 — "no groups" does not mean "nothing is created"
>
> The expectation going in was that the NamespaceConfig *could not create anything* without
> matching groups. **It creates everything.** Kubernetes RBAC does not validate that a subject
> exists — a `RoleBinding` naming a non-existent Group is accepted, stored, and reported
> healthy. It simply grants nobody.
>
> Confirmed independently: a `RoleBinding` referencing
> `this-group-definitely-does-not-exist-12345` was accepted by `oc apply --dry-run=server`.
>
> **Consequence:** a typo in `company.net/mnemonic`, or a group nobody created in LDAP, produces
> a namespace that looks correctly configured and grants no access. There is no error, no
> event, and no failed reconcile to alert on. `oc get rolebinding` is *not* evidence that
> access works.

## Step 2 — seed the missing groups in LDAP

Added `ldap-rbac-groups-spar-trno.ldif` to `setup-local-ldap-testing/`, creating six groups:
`app-ocp-rbac-{spar,trno}-ns-{admin,developer,audit}`.

```bash
POD=$(oc get pods -n ldap-testing -l app=openldap -o name | head -1)
oc cp ldap-rbac-groups-spar-trno.ldif ldap-testing/${POD#pod/}:/tmp/
oc exec -n ldap-testing ${POD#pod/} -- ldapadd -x -H ldap://localhost:389 \
    -D "cn=admin,dc=ephico2real,dc=com" -w admin123 \
    -f /tmp/ldap-rbac-groups-spar-trno.ldif
```

> ### GOTCHA 2 — mixed user DN forms (since FIXED)
>
> At the time of this run, some users were `cn=john.doe,ou=People,...` and others
> `uid=sarah.jones,ou=People,...`. The operator matches members **by DN**, so a `member:`
> line in the wrong form is accepted by `ldapadd` and then silently dropped at sync.
>
> This was not hypothetical — auditing the directory found **three already-broken groups**:
>
> ```
> app-ocp-rbac-devops-cluster-admin  -> uid=john.doe      (user was cn=john.doe)
> app-ocp-rbac-devops-ns-developer   -> uid=alice.cooper  (user was cn=alice.cooper)
> app-ocp-rbac-test-cluster-admin    -> uid=john.doe      (user was cn=john.doe)
> ```
>
> plus `uid=placeholder,...` referenced by three groups and never created. All synced empty.
>
> **Fixed** by `ldap-normalize-user-dns.ldif` in `setup-local-ldap-testing/`, which renames
> the five `cn=` users to `uid=`. The `refint` overlay is enabled on that server and tracks
> `member`, so all 68 member references were rewritten automatically by the rename — without
> it, every reference would need hand-editing.
>
> ```bash
> ldapsearch -x -b "ou=People,dc=ephico2real,dc=com" "(objectClass=inetOrgPerson)" dn
> # every DN now starts with uid=
> ```
>
> **Check `refint` before attempting a rename elsewhere:**
>
> ```bash
> ldapsearch -x -D "cn=admin,cn=config" -w <pw> -b "cn=config" \
>   "(objectClass=olcRefintConfig)" olcRefintAttribute
> ```

> ### GOTCHA 2b — repairing a broken group silently ACTIVATES its bindings
>
> Those three groups were not empty by design; they were broken. Their RoleBindings and
> ClusterRoleBindings existed the whole time, waiting on a group that never resolved.
> Fixing the DNs armed them on the next sync, with **no RBAC change and no approval step**:
>
> ```
> app-ocp-rbac-devops-cluster-admin-crb  ->  ClusterRole/admin  ->  john.doe
> app-ocp-rbac-test-cluster-admin-crb    ->  ClusterRole/admin  ->  john.doe
> ```
>
> `ClusterRole/admin` bound cluster-wide means namespace-admin in **every** namespace —
> verified in `kube-system`, `openshift-monitoring`, `demo-prod` and `spar-rnd`:
> `create rolebindings=yes`, `get secrets=yes`. It is *not* full cluster-admin — `delete
> nodes / namespaces / clusterrolebindings` all returned `no`, since `admin` excludes
> cluster-scoped resources.
>
> **Before repairing a broken group, check what its bindings grant.** A "fix the empty
> group" ticket can be a privilege grant in disguise. Audit first:
>
> ```bash
> oc get clusterrolebinding -o json | python3 -c "
> import sys,json
> for c in json.load(sys.stdin)['items']:
>     for s in c.get('subjects') or []:
>         if s.get('kind')=='Group':
>             print(c['metadata']['name'], '->', c['roleRef']['name'], '->', s['name'])"
> ```

## Step 3 — wait for the sync

`GroupSync/ldap-groupsync` runs `*/2 * * * *` with filter `cn=app-ocp-rbac-*`.

```
t=10s   synced=0/6
...
t=120s  synced=6/6
```

> ### GOTCHA 3 — the RoleBindings were never touched
>
> ```
> spar-admin-rb  created=2026-07-30T03:26:31Z
> group          created=2026-07-30T03:30:08Z
> ```
>
> The binding predates the group by ~4 minutes and was **not** modified when the group
> appeared. RBAC resolves subjects at authorization time, not at binding time, so access went
> live the moment the group synced. Nothing re-reconciled, and nothing needed to.
>
> This is the flip side of Gotcha 1: the same late-binding behaviour that makes the failure
> silent also makes the fix instant.

## Step 4 — verify access is real

```
ROLE-GROUP  CHECK                  RESULT
admin       create pods            yes
admin       delete pods            yes
admin       get pods               yes
admin       create rolebindings    yes
developer   create pods            yes
developer   delete pods            yes
developer   get pods               yes
developer   create rolebindings    no
audit       create pods            no
audit       delete pods            no
audit       get pods               yes
audit       create rolebindings    no
```

Exactly the intended model: admin can delegate, developer (`edit`) can work but not grant,
audit (`view`) can only read.

> ### GOTCHA 4 — `--as=<user>` alone silently reports "no"
>
> ```bash
> oc auth can-i create pods -n spar-rnd --as=jane.smith
> # no          <- WRONG conclusion
>
> oc auth can-i create pods -n spar-rnd --as=jane.smith \
>     --as-group=app-ocp-rbac-spar-ns-admin
> # yes         <- correct
> ```
>
> Impersonation uses **only** the groups you pass with `--as-group`. It does not resolve
> OpenShift `Group` objects, so a user whose access comes entirely from group membership
> tests as having none. The real OAuth login path *does* resolve groups — so this is a
> testing artefact that looks exactly like a broken policy.

> ### GOTCHA 5 — `can-i --as-group` is NOT a test for "does anyone have access"
>
> Impersonation lets you **assert membership of a group that does not exist**, and the
> authorizer only string-matches the group name in the RoleBinding:
>
> ```bash
> oc get group app-ocp-rbac-zzzz-ns-admin
> # Error from server (NotFound)
>
> oc auth can-i create pods -n zzzz-rnd --as=test-user \
>     --as-group=app-ocp-rbac-zzzz-ns-admin
> # yes          <- but nobody can ever obtain that group
> ```
>
> That `yes` proves the *binding is wired correctly*. It says nothing about whether a real
> user can use it. The check that actually distinguishes a working binding from a dead one is
> group existence and membership:
>
> ```bash
> oc get rolebinding -n <ns> \
>   -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .subjects[*]}{.name}{end}{"\n"}{end}' \
> | while IFS=$'\t' read -r rb grp; do
>     u=$(oc get group "$grp" -o jsonpath='{.users}' 2>/dev/null)
>     echo "$rb -> $grp -> ${u:-GROUP DOES NOT EXIST}"
>   done
> ```
>
> Side-by-side, the bindings are indistinguishable; only the group lookup separates them:
>
> | Namespace | Subject group | Real members |
> |---|---|---|
> | `zzzz-rnd` | `app-ocp-rbac-zzzz-ns-admin` | **does not exist → nobody, ever** |
> | `zzzz-rnd` | `bda-rbac-spark-gamma-users` | **does not exist → nobody, ever** |
> | `spar-rnd` | `app-ocp-rbac-spar-ns-admin` | `["jane.smith"]` |
> | `spar-rnd` | `bda-rbac-spark-alpha-users` | `["jane.smith","bob.wilson"]` |

> ### GOTCHA 6 — `oc auth can-i` writes "no" to stderr
>
> `RESULT=$(oc auth can-i ... 2>/dev/null)` captures an **empty string** for every denial.
> A verification loop written that way prints blanks and looks broken. Use `2>&1`.

## Step 5 — apply the BDA config

```bash
oc apply -f working-sessions/bda-namespace-config.yaml
```

Created in every matching namespace, alongside the standard RBAC:

```
spar-rnd
  Role/bda-workload-submitter-role
  RoleBinding/spark-alpha-users-bda-workload-submitter-rb
      -> Role/bda-workload-submitter-role   subj=bda-rbac-spark-alpha-users
spar-qa
  RoleBinding/spark-alpha-apps-bda-workload-submitter-rb
      -> subj=bda-rbac-spark-alpha-apps
trno-uat
  RoleBinding/trino-theta-users-bda-workload-submitter-rb
      -> subj=bda-rbac-trino-theta-users
```

One policy, three services, one group each — the label picks which. Members came straight from
LDAP (`bda-rbac-spark-alpha-users` → `jane.smith, bob.wilson`), and access was live with no
further action.

Effective access, confirming the Role is genuinely narrower than `edit`:

```
create pods              yes
delete pods              yes
get pods                 yes
get secrets              yes
list secrets             no     <- no "list" verb on secrets
update configmaps        no     <- no "update" verb at all
create rolebindings      no
```

> ### GOTCHA 7 — BDA access is additive, not a replacement
>
> A BDA namespace ends up with **four** RoleBindings: the three standard ones plus the BDA one.
> They target different groups, so this is coherent — but `ClusterRole/edit` (held by the
> `-ns-developer` group) is a strict superset of `bda-workload-submitter-role`. Anyone in both
> groups gains nothing from the BDA binding. Its value is granting a *separate* population a
> narrower set.

> ### GOTCHA 8 — `secrets: watch` without `list`
>
> Carried over verbatim from `bdp-namespace-config.yaml`. `watch` on the collection still lets
> a subject enumerate every secret, so it does not restrict visibility, while the missing
> `list` breaks plain `oc get secrets` (shown as `list secrets -> no` above). Also note
> `secrets:get` + `pods:create` is close to reading every secret in the namespace, since any
> secret can be mounted into a new pod. Decide this deliberately rather than inheriting it.

## Verifying — resolve the bindings, don't just list them

`oc get rolebinding` cannot tell a working binding from a dead one. Run:

```bash
./working-sessions/verify-bda-rolebindings.sh
```

```
##### spar-rnd #####
  RoleBinding : spark-alpha-users-bda-workload-submitter-rb
  roleRef     : Role/bda-workload-submitter-role
  subject     : Group/bda-rbac-spark-alpha-users   -> members=bob.wilson,jane.smith
  from label  : spark-alpha-users
  source cfg  : bda-workload-submitter-namespaceconfig-rbac

##### spar-qa #####
  subject     : Group/bda-rbac-spark-alpha-apps    -> members=john.doe

##### trno-uat #####
  subject     : Group/bda-rbac-trino-theta-users   -> members=bob.wilson

##### zzzz-rnd #####
  subject     : Group/bda-rbac-spark-gamma-users   -> GROUP MISSING
```

**`zzzz-rnd` is the point.** In plain `oc get rolebinding` output it is indistinguishable
from the three above — same name pattern, same `roleRef`, same age, same `managed-by`
label, same source annotation, and the operator reports `ReconcileSuccess`. The only
difference is that its subject does not resolve. It grants nobody and always will.

The script reports three states, and they are not the same problem:

| State | Meaning | What to do |
|---|---|---|
| `members=<names>` | Working | nothing |
| `group exists but EMPTY` | Group synced, nobody in it in LDAP. Grants nobody **today** — and arms the moment someone is added upstream, with no RBAC change | check the LDAP group is meant to be empty; see Gotcha 2b |
| `GROUP MISSING` | No such Group object — a typo'd namespace label, or a group never created in LDAP | fix the label, or seed the group |

It also prints the traceability chain, so a mismatch is obvious: the `from label` value
should equal the RoleBinding name prefix **and** the group suffix. For `spark-alpha-users`
all three agree.

> `oc auth can-i --as-group=<name>` is **not** a substitute. Impersonation lets you assert
> membership of a group that does not exist and answers `yes` — proving the binding is
> wired correctly, not that any real user can use it. See Gotcha 5.

Defaults are overridable, so the same script covers other families:

```bash
LABEL=company.net/bda-team SUFFIX=bda-workload-submitter-rb ./verify-bda-rolebindings.sh
```

## How NCO tracks and cleans up what it creates

Worth knowing before assuming anything about drift, because the intuitive read from the
Kubernetes side is wrong.

**`ownerReferences` is empty** on every object NCO creates. The obvious inference — that
Kubernetes garbage collection cannot cascade, so orphans accumulate — is **incorrect**. NCO
does its own tracking, and it is thorough.

### Cleanup: verified, all three cases

| Scenario | Result | Evidence |
|---|---|---|
| Delete the NamespaceConfig | ✅ full cleanup | 3 RoleBindings **and** 3 Roles removed across 3 namespaces |
| Change a namespace label so a **different object name** is derived | ✅ old object removed | relabelled `oud-poc-trino`; `bda-rbac-trino-alpha-users-rb` deleted, `bda-rbac-spark-theta-apps-rb` created |
| Namespace stops matching the selector | ✅ full cleanup | removed the label from `oud-poc-crossfamily`; Role and RoleBinding both gone |

> **A retracted claim.** An earlier draft of this document marked the middle row
> "❌ orphan", reasoning from the empty `ownerReferences`. That was inference, not
> measurement, and it was wrong — NCO cleans up on relabel. Any migration plan built on
> "relabelling orphans the old binding" is unnecessary.

### The mechanism, from the CRD

The `NamespaceConfig` CRD describes `excludedPaths` as:

> *"json paths that need not be considered by the **LockedResourceReconciler**"*

NCO runs **one controller per managed resource**. Visible in the operator log:

```
controller_locked_object_rbac.authorization.k8s.io/v1/Role/oud-poc-trino/oud-group-submitter-role
controller_locked_object_rbac.authorization.k8s.io/v1/RoleBinding/oud-poc-trino/bda-rbac-trino-alpha-users-rb
```

That per-object controller is the tracking, which is why no `ownerReferences` are needed.

The CRD also declares `status.lockedResourceStatuses` — *"reconcile status for each of the
managed resources"* — but on this version it is **empty** on every NamespaceConfig checked,
including long-lived ones. The tracking is real; it is just not surfaced in status, so the
operator log is the place to look.

`excludedPaths` has **no CRD default**. The operator injects one at runtime — a template
declaring `['.metadata', '.status']` is stored as `['.metadata', '.status', '.spec.replicas']`.

### Two independent layers — this is the part that trips people

| Layer | Scope | Behaviour |
|---|---|---|
| **Lifecycle** | the whole object | always tracked; deleted on CR-delete, relabel, or unmatch |
| **Field enforcement** | paths *within* the object | `excludedPaths` are left alone |

Every NamespaceConfig in this repo excludes `.metadata`, so those two layers produce
different answers for different edits. Verified by changing one of each:

```
spec change      pods/log verbs ["get","list"] -> ["get","list","watch"]
                 propagated automatically, no delete needed, and reverted the same way

metadata change  adding an annotation to the template
                 did NOT propagate — required delete + recreate
```

> ### GOTCHA 9 — template metadata edits do not reach existing objects
>
> Because `.metadata` is in `excludedPaths` on every NamespaceConfig here, editing labels or
> annotations in an `objectTemplate` changes **nothing** on objects that already exist.
> `oc apply` succeeds, the operator reports `ReconcileSuccess`, and the old metadata stays
> indefinitely. Only newly created objects pick it up, so a cluster ends up with two
> generations carrying different metadata.
>
> That matters when the metadata is *selected on*. The orphan-cleanup query below only finds
> objects created **after** the label was added to the template:
>
> ```bash
> oc get rolebinding -A -l rbac.ocp.io/config-source=<short name>       # nonprod-rbac, prod-rbac, …
> ```
>
> To roll metadata forward, delete and let NCO rebuild:
>
> ```bash
> oc delete rolebinding -A -l rbac.ocp.io/config-source=<short name>
> ```
>
> **Select on `config-source`, not on `source-namespaceconfig` — corrected 2026-08-14.** These two
> commands originally used `source-namespaceconfig`, which was right when oud-group was the only
> policy here: it sets that key as a **label**. Every policy the chart added since sets it as an
> **annotation** instead, and `oc -l` matches labels only — so on those the selector matches zero
> objects and a delete reads as a clean no-op. Measured per family:
>
> ```
> -l rbac.ocp.io/source-namespaceconfig=nonprod-namespaceconfig-rbac    0  (of 30)
> -l rbac.ocp.io/config-source=nonprod-rbac                           30
> -l rbac.ocp.io/source-groupconfig=baseline-cluster-groupconfig-rbac   0  (of 12)
> -l rbac.ocp.io/config-source=cluster-rbac                           12
> -l rbac.ocp.io/source-namespaceconfig=abc-oud-group-namespaceconfig-rbac  3  (of 3 — the exception)
> ```
>
> So `config-source` for everything the chart renders; `source-namespaceconfig` only for oud-group,
> which carries no `config-source` at all. The annotation placement is itself deliberate — provenance
> is not meant to be a selector — which is precisely why a selector built on it fails, and fails
> *quietly*. See `docs/labels-and-annotations.md` §3.2 for the underlying key inconsistency.
>
> This is arguably the right default — it stops NCO fighting other controllers that annotate
> resources — but it is silent, and it is the *only* drift case NCO does not self-heal.
> Everything at the object level does.

## Kyverno gotchas

Found while repairing `policies/kyverno-validation-only.yaml`. All three cost real time and
none of them announce themselves.

> ### GOTCHA 10 — `validate.pattern` is NOT regex
>
> Every rule in this repo that put a regex in `validate.pattern` was broken. `validate.pattern`
> does **wildcard** matching (`*`, `?`) and treats `|` as its own **OR operator**. Three rules,
> three different failure shapes:
>
> | Rule | Symptom |
> |---|---|
> | `validate-mnemonic-format` | failed **everything** — 14 false positives, incl. `beta-prod` (mnemonic `beta`) |
> | `validate-environment-values` | failed **first and last** alternatives only — 8 false positives |
> | `validate-custom-clusterroles-format` | validated an **impossible** value, never ran |
>
> The middle one is the dangerous one. `"^(rnd|eng|qa|uat|prod)$"` was split on `|` into five
> alternatives:
>
> ```
> ^(rnd  |  eng  |  qa  |  uat  |  prod)$
>  ^^^^                            ^^^^^
>  welded to "^("                  welded to ")$"
> ```
>
> The middle three are clean literals and matched. The first and last carry the anchors and
> could never match — so `qa` and `uat` passed while `rnd` and `prod` always failed.
>
> **A rule that fails everything looks broken. One that fails plausibly looks like it works.**
> That is how this survived, and under Enforce it would have rejected every production
> namespace.
>
> `regex_match()` inside `deny.conditions` is the correct idiom:
>
> ```yaml
> deny:
>   conditions:
>     all:
>     - key: "{{ regex_match('^(rnd|eng|qa|uat|prod)$', request.object.metadata.labels.\"company.net/app-environment\") }}"
>       operator: Equals
>       value: false
> ```
>
> 22 false positives eliminated across the three rules.

> ### GOTCHA 11 — narrowing a rule leaves STALE findings in the report
>
> After adding an `exclude` block, the report still showed all 115 findings — identical counts
> — which looked like the fix had failed. It had not. Admission was correct immediately:
>
> ```
> openshift-testexcl   ACCEPT (excluded)
> app-testincl         REJECT (rule applies)
> ```
>
> The cause is in the per-result timestamps:
>
> ```
> openshift-* results   23:06:01   <- before the exclude was applied
> app namespaces        23:12:52   <- after
> ```
>
> **Once a resource becomes excluded, Kyverno stops evaluating it — and therefore never
> rewrites its old result.** The stale `fail` lingers indefinitely. The max timestamp across
> the report looks fresh, because the *still-evaluated* resources keep updating.
>
> Force a rebuild after narrowing any rule's scope:
>
> ```bash
> oc delete clusterpolicyreport --all
> ```
>
> Expect several minutes on a cluster with ~130 namespaces. After rebuild: 115 → 45, with the
> 45 being genuine findings.
>
> **Do not measure a scope change without regenerating first** — the report will overstate.

> ### GOTCHA 12 — a label value cannot hold a list
>
> `validate-custom-clusterroles-format` validated a comma-separated list held in a **label**.
> That value cannot exist. The API restricts label values to:
>
> ```
> (([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])?
> ```
>
> which excludes both `,` and ` `. Verified against the live API:
>
> ```
> "database-admin,security-policy-admin"    -> rejected
> "database-admin, security-policy-admin"   -> rejected
> "database-admin"                          -> accepted
> ```
>
> So the apiserver rejected any multi-role value **before Kyverno ever saw it**, and the rule
> reported `skip` on every namespace — unused because it was unusable. A list has to be an
> **annotation**, which has no such restriction.
>
> Same constraint bit the `company.net/oud-group` design: `system:`-prefixed role names cannot
> be label values either, because of the colon.
>
> **When a label is supposed to carry structure, check it against the API's value regex first.**
> `skip` on every resource is the tell — it usually means unusable, not unused.

## Regression tests for these rules

`kyverno-label-test-namespaces.yaml` creates eight namespaces that exercise every namespace-label
rule, pass and fail, each named for what it proves.
`verify-kyverno-label-tests.sh` compares actual verdicts against the expectations declared in the
YAML header and **exits non-zero on a mismatch**, so a policy edit can be gated on it rather than
eyeballed.

```
NAMESPACE                    RULE                          EXPECT  ACTUAL
klt-pass-mnemonic-3char      consistency-app-ocp-rbac      pass    pass    ok
klt-fail-bad-env             validate-environment-values   fail    fail    ok
klt-fail-mnemonic-toolong    consistency-app-ocp-rbac      fail    fail    ok
ocp-klt-excluded-no-labels   require-rbac-labels           absent  absent  ok
...
ALL EXPECTATIONS MET
```

`absent` is the interesting expectation — it asserts Kyverno produced **no result at all**, which
is what distinguishes "excluded" from "passed". `klt-fail-bad-env` guards the Gotcha 10
regression specifically, since `prod` was one of the two alternatives the broken pattern could
never match.

```bash
oc apply -f working-sessions/kyverno-label-test-namespaces.yaml
./working-sessions/verify-kyverno-label-tests.sh
oc delete ns -l rbac.ocp.io/test-fixture=kyverno-labels   # teardown
```

## Why `bdp-namespace-config.yaml` was replaced

It derived group names as `app-ocp-rbac-bdp-spark-<label>`. **Zero** groups on the cluster match
that pattern, so every RoleBinding it created would have hit Gotcha 1 — created, healthy,
granting nobody.

The groups that actually exist come from `GroupSync/bda-rbac-groupsync`
(filter `cn=bda-rbac-*`) and are named `bda-rbac-<service>-<tenant>-<kind>`. 15 of them, all
populated. `bda-namespace-config.yaml` changes only the derivation; the Role's rules are
carried over verbatim so that adapting *matching* does not silently change *access*.

> ### GOTCHA 13 — two different "environment" axes
>
> ```
> company.net/app-environment   rnd | eng | qa | uat | prod   <- lifecycle stage
> tenant token in group name    alpha | delta | gamma | theta <- BDA tenant
> ```
>
> `bda-rbac-spark-alpha-users` says nothing about rnd vs prod. A namespace carries both;
> neither implies the other.

## Known data gap

`bda-rbac-spark-gamma-apps` exists but `bda-rbac-spark-gamma-users` does **not**. A namespace
labelled `company.net/bda-team: spark-gamma-users` would hit Gotcha 1. Check before labelling:

```bash
oc get group bda-rbac-<service>-<tenant>-<kind>
```

A Kyverno rule to validate this at admission is planned. Note the constraint found while
checking: `kyverno-admission-controller` **cannot** read `groups.user.openshift.io`, while
`kyverno-background-controller` **can** — so an admission-time deny needs extra RBAC, whereas
an audit/report policy would work today.

## Teardown

```bash
oc delete -f working-sessions/bda-namespace-config.yaml
oc delete -f working-sessions/bda-namespace.yaml     # removes the 3 namespaces
# LDAP groups persist; remove them from the directory if not wanted:
#   ldapdelete -x -D "cn=admin,dc=ephico2real,dc=com" -w admin123 \
#     "cn=app-ocp-rbac-spar-ns-admin,ou=Groups,dc=ephico2real,dc=com"  # etc.
```
