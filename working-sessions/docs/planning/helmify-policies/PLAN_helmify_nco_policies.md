# Planning: Helmify the NCO CR policies (capturing the `bda` use case)

**Status: COMPLETE AND SUPERSEDED.** Implemented — the policies ship in the chart as
`chart/templates/rbac-policies/10-` … `13-`, and the labels they set were realigned in chart 0.8.0.
This document is kept as the decision record for *why* the design is what it is; it is **not** a
description of the current state. For that, read:

- `working-sessions/docs/labels-and-annotations.md` — the label/annotation contract
- `working-sessions/docs/templating-guide.md` — how the templates work
- `chart/templates/rbac-policies/_README.txt` — what each policy grants

The `exported/` directory this document referenced held a point-in-time dump of the live CRs as they
were **before** helmification. It has been removed: those CRs no longer exist in that form, and the
labels in them were retired in 0.8.0, so the files read as current manifests while being neither. They
remain in git history if the original state is ever needed.
**Branch:** `plan/helmify-policies-bda`
**Scope:** Whether/how to package the Namespace Configuration Operator (NCO) custom
resources (`GroupConfig` / `NamespaceConfig`) as a Helm chart, and how to extend them to
cover the `bda-rbac-*` group family. Operator *install* is a separate chart (`chart/`);
this is about the *policies*.

---

## 1. Objective

1. Package the NCO policy CRs so they deploy consistently (versioned, toggleable,
   environment-parameterized) instead of `oc apply -f policies/*.yaml`.
2. Extend coverage to the **`bda-rbac-*`** groups (Big-Data Analytics) synced by the new
   `bda-rbac-groupsync` CR, without breaking the existing `app-ocp-rbac-*` automation.
3. Do it **without fighting NCO's own templating** (the operator owns the runtime template
   language; Helm must not try to evaluate it).

## 2. Current state (exported, verified on cluster)

Live CRs at the time of writing (the `exported/` dump has since been removed — see the status note above):

| Kind | Name | In `policies/`? | Notes |
|---|---|---|---|
| GroupConfig | cluster-admin-groupconfig-rbac | ✅ | `-cluster-admin` → `admin` ClusterRoleBinding |
| GroupConfig | cluster-audit-groupconfig-rbac | ✅ | `-cluster-audit` → view |
| GroupConfig | cluster-developer-groupconfig-rbac | ✅ | `-cluster-developer` → edit |
| GroupConfig | database-admin-groupconfig-rbac | ✅ | dedicated group `platform-database-admins` |
| GroupConfig | user-workload-monitoring-admin-groupconfig-rbac | ✅ | monitoring access |
| GroupConfig | user-workload-monitoring-developer-groupconfig-rbac | ✅ | monitoring access |
| NamespaceConfig | nonprod-namespaceconfig-rbac | ✅ | env-aware (rnd/eng/qa/uat) → admin/edit/view |
| NamespaceConfig | prod-namespaceconfig-rbac | ✅ | prod → developer (`edit`) + audit (`view`), no admin — *as configured in this demo* |
| NamespaceConfig | multitenant | ✅ | NetworkPolicies for `multitenant: 'true'` namespaces — drift now closed, see below |

> **These role assignments are a worked example, not a production standard.** What this repo
> defines is the *mechanism*: the group-name patterns the policies match on, how those map to
> roles, and how namespace labels select an environment. **What production should actually grant
> is a company policy decision** — each organisation sets its own role map and adjusts the
> templates to match.
>
> The table records what these demo policies are configured to do *today*, which matters for the
> packaging work: an earlier revision said "prod → audit only", but `prod-namespaceconfig-rbac`
> as written creates **two** RoleBindings — `{mnemonic}-developer-rb` → `ClusterRole/edit` and
> `{mnemonic}-audit-rb` → `ClusterRole/view`. Verified on-cluster across `beta-prod`,
> `demo-prod` and `demo-production`.
>
> The distinction matters here specifically: whichever role map an organisation adopts, the chart
> must package the policies **as they are**. Building from a description that disagrees with the
> files would silently change access — in this case dropping the developer binding from every
> production namespace. Change the access model by editing the policy deliberately, never as a
> side effect of packaging it.

**Finding — config drift: CLOSED.** The `multitenant` NamespaceConfig ran on the cluster but
was not tracked in `policies/`. It is now committed as
[`policies/multitenant-namespaceconfig.yaml`](../../../policies/multitenant-namespaceconfig.yaml),
so the Helmify work starts from a repo that matches the cluster.

The committed copy is semantically identical to the live CR, not a byte-for-byte dump:

- `finalizers` was dropped — that is operator-managed runtime state, and applying it back
  would be wrong.
- The `objectTemplate` strings are stored as YAML block literals (`|`) rather than the escaped
  one-line form `oc get -o yaml` emits, so they are reviewable and diffable.
- Stray trailing whitespace in the live copy (`name: default········`) was stripped. YAML
  ignores it, so the rendered NetworkPolicies are unchanged.

Verified: `labelSelector` equal, both templates present with matching `excludedPaths`,
template[0] byte-identical and template[1] identical modulo that trailing whitespace.
`oc apply --dry-run=server -f policies/` accepts the whole directory.

**Remaining live-only resource — not exported.** `UserConfig/test-deletion-tracking-userconfig`
(created 2025-12-10) has `templates: []` and empty selectors, so it produces nothing. It is a
dead test artifact rather than a policy and is deliberately excluded from `policies/`; it should
be deleted from the cluster rather than adopted into source control.

### Group naming the policies key off

- Standard: `app-ocp-rbac-{mnemonic}-(ns|cluster)-(admin|developer|audit)`
- Dedicated: `platform-database-admins`, etc.
- Selection: every GroupConfig uses `labelSelector: {group-sync-operator.redhat-cop.io/sync-provider: Exists}`
  (i.e. *all* LDAP-synced groups), then the `objectTemplate` gates on the name suffix
  (`{{- if hasSuffix "-cluster-admin" .Name }}`).

## 3. The core challenge — two template engines, one file

Each policy's `objectTemplate` is a **string** full of NCO's own Go templating, evaluated by
the operator at reconcile time. Example (`cluster-admin-groupconfig-rbac`):

```text
{{- if hasSuffix "-cluster-admin" .Name }}
kind: ClusterRoleBinding
metadata:
  name: "{{ .Name }}-crb"
subjects:
- kind: Group
  name: "{{ .Name }}"
roleRef:
  kind: ClusterRole
  name: admin
{{- end }}
```

If this file is placed inside a Helm `templates/` directory, **Helm** tries to evaluate
`{{ .Name }}`, `hasSuffix`, `{{- if }}` at *chart render* time — it doesn't know `.Name`
(that's an NCO runtime value), so the render breaks or emits garbage. **Helm and NCO both
use `{{ }}`, but they run at different times (install vs reconcile).** This is exactly why
the operator said "the policies are already a template — don't fight that."

## 4. Options for helmifying

### Option A — Raw files, emitted verbatim (recommended)

Store the policies as **raw files** the chart does **not** template, and a thin template
that streams them through unchanged using `.Files.Get` / `.Files.Glob`:

```text
chart-policies/
  files/policies/*.yaml        # the CRs, byte-for-byte (NCO templates intact)
  templates/policies.yaml      # range over .Files.Glob, emit each verbatim
  values.yaml                  # which policies are enabled, + env parameters
```

```yaml
# templates/policies.yaml (sketch)
{{- range $path, $_ := .Files.Glob "files/policies/*.yaml" }}
{{ $.Files.Get $path }}
---
{{- end }}
```

`.Files.Get` returns bytes **without** running them through the template engine, so NCO's
`{{ .Name }}` survives untouched. Helm's value is what it's actually good at here:
**packaging, versioning, and enable/disable toggles** — not rewriting the NCO logic.

- ✅ Zero risk to the NCO templates (they're never evaluated by Helm)
- ✅ Simple, junior-readable, matches "don't fight the templates"
- ✅ Enable/disable per policy via values (glob a subset, or per-file `if`)
- ⚠️ Limited Helm-level parameterization *inside* a policy (see Option C if needed)

### Option B — Escape every NCO directive

Wrap each NCO `{{ ... }}` so Helm passes it through literally, e.g. ``{{ `{{ .Name }}` }}``
or `{{ "{{" }} .Name {{ "}}" }}`. This lets you Helm-parameterize inside the policy, **but**
every brace in every policy must be escaped — error-prone, unreadable, and precisely the
"fighting the templates" the operator rejected.

- ❌ High risk, high noise. Not recommended.

### Option C — Hybrid (raw body + templated envelope)

Keep the NCO-templated `objectTemplate` **body** as a raw file (Option A), but Helm-template
only the *outer* fields that contain **no** NCO directives — `metadata.name`,
`labelSelector`, `annotationSelector`, and which templates are included. Concretely: values
drive the CR envelope; the `objectTemplate` string is injected from a raw file via
`.Files.Get`.

- ✅ Real Helm parameterization (group prefixes, selectors, env) without touching NCO braces
- ⚠️ More moving parts than A; worth it **only** if we need to parameterize selectors/prefixes

**Recommendation:** start with **Option A** (package as-is, close the drift, get toggles),
and adopt **Option C** *only for the policies we need to parameterize* — which is exactly
the bda work (§5).

## 5. Capturing `bda` — the gap and the proposal

**Empirical finding (verified):** bda-rbac groups *do* carry the selector label
(`group-sync-operator.redhat-cop.io/sync-provider: bda-rbac-groupsync_ldap`), so the existing
GroupConfigs **select** them — but every template gates on
`hasSuffix "-cluster-admin"` / `-ns-admin` / `-cluster-developer` … and bda names end in
**`-apps` / `-users`**. So bda groups are selected and then produce **nothing**. They are
invisible to the current automation.

bda naming (from the group-sync work): `bda-rbac-{service}-{env}-{apps|users}`
(service ∈ spark|trino, env ∈ alpha|delta|theta, kind ∈ apps|users).

To capture bda we add a **new, dedicated policy family** (not a change to the app-ocp-rbac
ones) — a `bda-rbac-groupconfig` and/or `bda-rbac-namespaceconfig` whose templates gate on
the bda suffixes. Under Option C, the group prefix and role mapping become Helm values, so
the same template serves app-ocp-rbac and bda.

### OPEN QUESTIONS (need operator input before building)

The RBAC *intent* for bda is not derivable from the group names alone:

1. **What does each bda group grant?** e.g. does `bda-rbac-spark-alpha-users` bind to a
   **namespace** (which one — `spark-alpha`? a labelled set?) with which role (view/edit)?
   Does `-apps` mean service-account/CI access vs `-users` = human access?
2. **Namespace mapping.** app-ocp-rbac binds per-namespace via namespace labels
   (`company.net/mnemonic`, `app-environment`). What label(s) will bda namespaces carry, and
   how do `{service, env}` map to namespaces?
3. **Cluster vs namespace scope.** app-ocp-rbac has explicit `-cluster-*` vs `-ns-*` groups.
   bda has no such scope token — is bda always namespace-scoped?
4. **Env-awareness / prod restriction.** Should bda honour the same prod = audit-only rule?

Until these are answered, the bda policy can only be a **skeleton** — the plan captures the
*mechanism* (a new bda policy family, parameterized via Option C) and the *questions*, not a
guessed role map.

## 6. Proposed values shape (illustrative)

```yaml
policies:
  # Existing families — emitted verbatim (Option A), toggleable.
  appOcpRbac:
    clusterAdmin: true
    clusterDeveloper: true
    clusterAudit: true
    nonprodNamespace: true
    prodNamespace: true
  dedicated:
    databaseAdmin: true
    monitoringAdmin: true
    monitoringDeveloper: true
  multitenant: true            # drift closed — now in policies/

  # New parameterized family (Option C) — see OPEN QUESTIONS.
  bdaRbac:
    enabled: false             # off until the role map is decided
    groupPrefix: "bda-rbac-"
    # roleMap / namespaceSelector / envAware: TBD from §5 answers
```

## 7. Validation / rollout (shadow-first)

1. **Render-diff vs live.** `helm template` the Option-A policies and diff against the
   exported live CRs — must be byte-equivalent (proves packaging changed nothing).
2. **Dry-run.** `oc apply --dry-run=server` the rendered output.
3. **Drift close.** ~~Commit `multitenant`~~ — done, it is in `policies/`. Re-run the live-vs-repo
   comparison before building, in case new CRs have appeared since.
4. **bda skeleton** only after §5 answers; validate the emitted RoleBindings on one test
   namespace before enabling broadly.

## 8. Recommendation

- **Adopt Option A now** to package the existing 9 policies + close the `multitenant` drift,
  with per-policy enable/disable toggles. Low risk, immediate value, honours "don't fight
  the templates."
- **Design the bda family as Option C** — but **do not build it until the §5 OPEN QUESTIONS
  are answered.** The plan captures the mechanism and the questions; the role map is an
  operator decision, not a guess.

## 9. Next steps

1. Operator reviews §4 (Option A vs C) and answers §5 (bda RBAC intent).
2. On approval: build the Option-A policies chart + render-diff gate. (Drift already closed.)
3. Then: build the bda policy family per the answers, validate on a test namespace.
