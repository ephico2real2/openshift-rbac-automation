# How these templates work — `$group`, the derived variables, and the Helm functions

A guide to the four policy templates in `charts/namespace-configuration-operator/templates/rbac-policies/`. Everything here is taken from that code and
checked against the running cluster; where a claim has a number attached, the number was measured.

The single idea you need before anything else makes sense:

> **There are two template engines, they use the same `{{ }}` delimiters, and they run at different
> times.** Helm renders the file when you install. The operator renders each `objectTemplate` **later**,
> once per matching namespace or group. An expression meant for the operator has to survive Helm
> **unevaluated**.

Everything unusual in these templates follows from that one sentence.

---

## 1. The two phases, concretely

```
PHASE 1  helm upgrade                     PHASE 2  operator reconcile
─────────────────────────────             ──────────────────────────────────────
Helm reads charts/namespace-configuration-operator/values.yaml              The operator reads the CR from the cluster
Helm evaluates {{ }} it can see           For each matching namespace / group:
Result: a NamespaceConfig / GroupConfig      binds .Name and .Labels to that object
        CR, stored in etcd                   evaluates the objectTemplate STRING
                                             applies the resulting RoleBinding
```

`spec.templates[].objectTemplate` is a **YAML block scalar** — a string. Helm does not know it is a
template; it is just text being copied into a field. So any `{{ }}` left inside it reaches the cluster
and becomes the operator's input.

The problem is that Helm *will* evaluate anything it recognises. `hasSuffix` is a Sprig function Helm
has. `.Name` at chart top level is undefined. So a guard written naively is evaluated by Helm, against
nil, and **silently renders the binding away with no error**. That failure mode is why the code looks
the way it does.

### The technique: build the operator's template as a *string*

```gotemplate
{{- $group := "{{ .Name }}" }}
```

Helm sees a **string literal**. It assigns it. It does not recurse into the contents of a string it just
produced. When `{{ $group }}` is later written into the objectTemplate body, the six characters
`{{ .Name }}` are emitted verbatim and the operator evaluates them.

The same trick carries a whole conditional:

```gotemplate
{{- $guard  := printf "{{- if hasSuffix %s%s%s .Name }}" "\"" $suffix "\"" }}
{{- $endif  := "{{- end }}" }}
```

`$guard` is a string that *contains* an `if` action. Helm never runs it.

---

## 2. `$group` — the question you asked

There is no single `$group`. **Three different mechanisms**, chosen by what the CRD is keyed on and by
how that family names its groups. This is the whole answer:

| template | CRD | keyed on | `$group` is built from | resolved by |
|---|---|---|---|---|
| `11-baseline-groupconfig` | GroupConfig | a **Group** | `"{{ .Name }}"` | operator |
| `13-custom-groupconfig` | GroupConfig | a **Group** | `"{{ .Name }}"` | operator |
| `10-baseline-namespaceconfig` | NamespaceConfig | a **Namespace** | `printf "%s-%s-ns-%s" $b.groupPrefix $mn $r.name` | **both** |
| `12-custom-oud-group` | NamespaceConfig | a **Namespace** | `printf "{{ index .Labels %s%s%s }}" ...` | operator |

### 2a. GroupConfig — the group is the identity

```gotemplate
{{- $group := "{{ .Name }}" }}
```

A GroupConfig selects Groups, so the operator's `.Name` **is** the group name. Nothing to derive. The
narrowing is done by the per-template guard:

```gotemplate
{{- $suffix := printf "-cluster-%s" $r.name }}      {{/* -cluster-admin */}}
{{- $guard  := printf "{{- if hasSuffix %s%s%s .Name }}" "\"" $suffix "\"" }}
```

The operator evaluates that guard once per selected group. **A template whose guard is false renders
empty, and the operator is fine with that** — measured before this consolidation: 63 synced groups
against 3 templates is 189 evaluations producing 12 ClusterRoleBindings, so 177 already rendered empty
with no ill effect.

### 2b. Baseline NamespaceConfig — composed across BOTH phases

This is the interesting one, and it is why "auto-detect" is the right instinct.

```gotemplate
{{- $mn    := printf "{{ index .Labels %s%s%s }}" "\"" $b.mnemonicLabelKey "\"" }}
{{- $group := printf "%s-%s-ns-%s" $b.groupPrefix $mn $r.name }}
```

Read it in two steps:

1. **Helm** builds `$mn` as the *string* `{{ index .Labels "company.net/mnemonic" }}`.
2. **Helm** then interpolates that string into the middle of `$group`, giving:

```
app-ocp-rbac-{{ index .Labels "company.net/mnemonic" }}-ns-admin
   ↑ literal, from values      ↑ deferred to the operator            ↑ literal, from the role entry
```

So one value is half-resolved at install time and half at reconcile time. The operator finishes it per
namespace:

```
namespace beta-rnd, label company.net/mnemonic=beta
  →  app-ocp-rbac-beta-ns-admin
```

**That is the auto-detection.** The policy never lists groups. It selects namespaces that carry the
mnemonic label, reads the value, and *computes* the group name from the naming convention. Add a
namespace with `company.net/mnemonic=zeta` and the bindings for `app-ocp-rbac-zeta-ns-*` appear on the
next reconcile with no chart change.

The convention is not invented here — `working-sessions/policies/kyverno-group-naming-app-ocp-rbac.yaml`
already validates `app-ocp-rbac-{mnemonic}-(ns|cluster)-(admin|developer|audit)`. `groupPrefix` plus the
derived `ns-<name>` is that existing rule expressed in values.

**The consequence to know:** the group is *assumed to exist*. If `app-ocp-rbac-zeta-ns-admin` is not in
LDAP, the RoleBinding is still created and grants nobody — it references a Group with no members. That
is not an error anywhere; it is why `working-sessions/scripts/add-missing-rbac-groups.ldif` exists.

### 2c. oud-group NamespaceConfig — the label value *is* the group

```gotemplate
{{- $group := printf "{{ index .Labels %s%s%s }}" "\"" $p.labelKey "\"" }}
```

No prefix, no composition, no tier suffix. Whatever `company.net/oud-group` holds is used verbatim as
the group name. This is the axis the CR label `rbac.ocp.io/group-naming: namespace-label` records, as
against `pattern` for the other three.

It is also why this policy is structurally separate rather than an `if` inside `10-baseline-`: one
selector expression, a Role of its own, and a group name that is read rather than computed.

### 2d. Why `| quote` is never used on these

```gotemplate
{{- $mn := printf "{{ index .Labels %s%s%s }}" "\"" $b.mnemonicLabelKey "\"" }}
```

The quotes are passed to `printf` as **arguments** — that is what the `%s%s%s` with `"\""` is doing.
The obvious alternative fails:

```gotemplate
{{- $bad := printf "{{ index .Labels %s }}" ($b.mnemonicLabelKey | quote) }}
{{/* emits:  {{ index .Labels \"company.net/mnemonic\" }}   */}}
```

`quote` produces a *Go-escaped* string. The operator renders each objectTemplate **as a Go template
first and parses the result as YAML second** — so at render time a `\"` is not an escape, it is a
backslash inside an action, and the parse fails. The quotes must be literal characters.

### 2e. `#` is a YAML comment, NOT a Helm comment

```gotemplate
# rbac.ocp.io/group-name will be {{ .Name }}      <-- WRONG: Helm evaluates this
```

Helm processes the file as **text** before YAML ever sees it, so an action inside a `#` line is
evaluated like any other. That is why the headers in these templates describe the operator's
expressions in prose instead of quoting them. Helm's real comment is `{{/* ... */}}`.

---

## 3. Every derived value, per template

`name` and `clusterRole` are the only irreducible fields in a role entry. Everything else is computed —
which is the point: fewer values keys, no chance of two fields disagreeing.

### `10-baseline-namespaceconfig-rbac.yaml` — from `roles[].name` + `clusterRole`

| output | expression | example (`name: audit`) |
|---|---|---|
| RoleBinding name | `{{ $mn }}-{{ $r.name }}-rb` | `beta-audit-rb` |
| RoleBinding namespace | `{{ $ns }}` = `{{ .Name }}` | `beta-rnd` |
| subject group | `$group` (see §2b) | `app-ocp-rbac-beta-ns-audit` |
| `rbac.ocp.io/role-type` | `ns-{{ $r.name }}` | `ns-audit` |
| `rbac.ocp.io/bound-role` | `{{ $r.clusterRole }}` | `view` |
| `rbac.ocp.io/scope` | literal | `namespace-scoped` |
| `rbac.ocp.io/mnemonic` | `{{ $mn }}` | `beta` |
| `rbac.ocp.io/environment` | `{{ $env }}` | `rnd` |
| `roleRef` | `ClusterRole/{{ $r.clusterRole }}` | `ClusterRole/view` |

`clusterRole` stays explicit because it is **not derivable from the tier name** — `developer` → `edit`,
`audit` → `view` — and it is the field an auditor actually reads.

### `11-baseline-groupconfig-rbac.yaml` — from `roles[].name` + `clusterRole`

| output | expression | example (`name: audit`) |
|---|---|---|
| guard suffix | `-cluster-{{ $r.name }}` | `-cluster-audit` |
| ClusterRoleBinding name | `{{ $group }}-crb` | `app-ocp-rbac-alpha-cluster-audit-crb` |
| `rbac.ocp.io/role-type` | `cluster-{{ $r.name }}` | `cluster-audit` |
| `rbac.ocp.io/bound-role` | `{{ $r.clusterRole }}` | `view` |
| `group-pattern` annotation | `{{ $c.groupPrefix }}-*{{ $suffix }}` | `app-ocp-rbac-*-cluster-audit` |
| `roleRef` | `ClusterRole/{{ $r.clusterRole }}` | `ClusterRole/view` |

Note the tier names do **not** match the ClusterRoles: tier `cluster-audit` binds `view`, tier
`cluster-admin` binds `admin`. Two keys, two facts — `role-type` for the tier, `bound-role` for the
role.

### `12-custom-oud-group-namespaceconfig-rbac.yaml`

| output | expression |
|---|---|
| Role name | `{{ $p.roleName }}` — fixed, **one per namespace**, not per group |
| RoleBinding name | `{{ $group }}-rb` |
| subject group | `$group` = the `company.net/oud-group` label value |
| `rbac.ocp.io/role-type` | `{{ $p.roleType }}` |
| `rbac.ocp.io/bound-role` | `{{ $p.roleName }}` (a Role, not a ClusterRole) |
| `roleRef` | `Role/{{ $p.roleName }}` |

The Role object deliberately carries **no** `bound-role` and no `group-name`: it *is* the role rather
than referencing one, and it is shared per namespace, so naming a single group on it would be wrong
rather than merely redundant.

### `13-custom-groupconfig-rbac.yaml` — free-form

| output | expression |
|---|---|
| guard suffix | `{{ $entry.suffix }}` (must start with `-`; guarded) |
| binding kind | `RoleBinding` if `scope: namespace`, else `ClusterRoleBinding` |
| binding name | `{{ $group }}-{{ $bind }}` where `$bind = default $entry.name $entry.bindingSuffix` |
| `rbac.ocp.io/role-type` | `{{ $entry.name }}` |
| `rbac.ocp.io/bound-role` | `{{ $entry.clusterRole }}` |
| `rbac.ocp.io/scope` | from `$entry.scope` |
| `roleRef` | `ClusterRole/{{ $entry.clusterRole }}` |

`$bind` exists because the default name **stutters** when the entry name repeats the suffix: entry
`database-admin` with suffix `-database-admin` gives
`app-ocp-rbac-alpha-database-admin-database-admin`. Setting `bindingSuffix: crb` gives
`app-ocp-rbac-alpha-database-admin-crb`.

---

## 4. The Helm / Sprig functions these templates use

Counted from the actual chart, most-used first. Helm ships Sprig, so most of these are Sprig rather
than Helm proper.

| function | what it does | how it is used here |
|---|---|---|
| `printf` | Go `fmt.Sprintf` | **the workhorse** — builds every deferred operator expression and every `fail` message |
| `include` | render a named template | `include "nco.labels" .` for the shared CR label block |
| `nindent N` | newline + indent every line by N | `include … \| nindent 4` — required because the included block is multi-line |
| `fail "msg"` | abort the render with a message | 19 uses; every guard that would otherwise ship a silent no-op |
| `index M "k"` | look up a map key | reads a namespace label — **deferred to the operator**, never run by Helm |
| `hasSuffix "s" x` | string suffix test | inside the deferred guard string, so the *operator* runs it |
| `hasPrefix "-" x` | string prefix test | Helm-side guard: refuses a suffix missing its leading hyphen |
| `default A B` | B if B is non-empty, else A | `default $entry.name $entry.bindingSuffix` |
| `dict` / `set` / `hasKey` | build and probe a map | the duplicate-`bindingSuffix` detector |
| `range` | iterate | over `roles` / `entries` / `policies` |
| `has x list` | membership | `has $entry.scope (list "cluster" "namespace")` |
| `quote` | wrap in double quotes, Go-escaped | CR-level scalars only — **never** on a deferred expression (§2d) |
| `toYaml` | marshal a value to YAML | `rules` and `excludedPaths` from values |
| `empty` / `not` / `and` / `or` / `eq` | logic | the guard conditions |
| `with` | scope to a value if non-empty | optional blocks |
| `toString` | coerce for a message | so a non-string `scope` still prints in the `fail` |
| `replace` / `trunc` / `trimSuffix` | string surgery | `helm.sh/chart` label in `_helpers.tpl` |

### The `fail` pattern, and why there are 19 of them

```gotemplate
{{- if not $c.syncProviderLabelKey }}
{{- fail "customGroupConfig.syncProviderLabelKey is empty. It is the ONLY thing narrowing this
policy to synced groups, so empty would select every Group on the cluster and bind your custom
roles to all of them. Set it, or disable customGroupConfig." }}
{{- end }}
```

Every one of these guards a case where the *quiet* outcome is worse than an error. An empty selector
does not fail — it matches everything. An empty `roles` list does not fail — it renders a CR that
selects namespaces and grants nothing. The message always says what the bad outcome would be, not just
which field is missing.

### `_helpers.tpl`

```gotemplate
{{- define "nco.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "nco.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}
```

`trunc 63` because a label **value** is limited to 63 characters; `trimSuffix "-"` because truncation
can leave a trailing hyphen, which is not a legal label value. This block is the single source of
`app.kubernetes.io/version` — see the labels reference for why it must not be set by hand on objects.

Note `include "nco.labels" $` in `10-baseline-` rather than `.`: inside a `range`, `.` is the loop
item, so the root context has to be passed explicitly as `$`.

---

## 5. Verifying a change

**An `objectTemplate` is not valid YAML until it is rendered.** Never hand one to a YAML parser
directly — it will fail on the `{{- if … }}` line, and that failure tells you nothing.

The working method: render the operator's expressions out, *then* parse.

```python
import subprocess, yaml, re
out = subprocess.run(["helm","template","t","chart",
    "--set","namespaceConfigPolicy.enabled=true",
    "--set","namespaceConfigPolicy.baseline.enabled=true",
    "--set","clusterRbac.enabled=true",
    "--set","customGroupConfig.enabled=true",
    "--set","namespaceConfigPolicy.oudGroup.enabled=true"],
    capture_output=True, text=True, check=True).stdout

def render(ot):
    s = re.sub(r"\{\{-?\s*if [^}]*\}\}", "", ot)          # drop the operator's guards
    s = re.sub(r"\{\{-?\s*end\s*\}\}", "", s)
    s = re.sub(r"\{\{\s*index \.Labels [^}]*\}\}", "<label>", s)
    s = re.sub(r"\{\{\s*\.Name\s*\}\}", "<name>", s)
    return yaml.safe_load(s)

for d in yaml.safe_load_all(out):
    if d and d.get("kind") in ("NamespaceConfig", "GroupConfig"):
        for t in d["spec"]["templates"]:
            obj = render(t["objectTemplate"])
            print(d["metadata"]["name"], obj["kind"], obj["metadata"]["labels"])
```

**Two cautions learned the hard way on this chart:**

- **Do not collapse distinct expressions into one placeholder** and then compare values. Substituting
  every `index .Labels` with the same token made `mnemonic` and `environment` look like duplicates.
  They are not — the live objects read `beta` and `rnd`. A rendered template is evidence about the
  *template*; only the live object is evidence about the *object*.
- **Do not diff objectTemplates as strings.** `toYaml` emits block style where a hand-written source
  used flow style (`[""]`), so identical specs diff as different. Parse both, compare the dicts.

Verify on the cluster with `oc get -o json`, not by reading the template — and remember **GOTCHA 9**:
the operator injects `excludedPaths: [.metadata, .status, .spec.replicas]`, so a metadata change in an
objectTemplate reaches **nothing that already exists**. Delete the CRs and let it rebuild. Measured:
55 objects revoked in ~4s, restored within ~50s.

Select on `rbac.ocp.io/config-source` for that delete — **not** on `source-namespaceconfig`, which is
an annotation, and `oc -l` matches labels only.

---

## 6. Where the files live — `templates/rbac-policies/`

The four policy templates sit in a **subdirectory** of `templates/`, so the access policies are separated
from the templates that install the operator. **Helm walks `templates/` recursively**, so this changes
nothing about rendering. Verified when the folder was introduced — the rendered output before and after
the move was identical apart from the `# Source:` path comment:

```
before:  1749 lines, 18 resources
after:   1749 lines, 18 resources
diff (ignoring "# Source:" lines):  no differences
```

- **`_helpers.tpl` still resolves from a subdirectory.** A chart has ONE template namespace regardless of
  layout, so `include "nco.labels"` works from anywhere in the chart.
- **Install order is unaffected.** Helm orders by resource **kind**, not by path or filename; the
  `10`–`13` prefixes are a reading order for humans. ArgoCD ordering comes from the
  `argocd.argoproj.io/sync-wave` annotation on each CR.

### The trap: every file in `templates/` is rendered

A plain `README.md` dropped in there is treated as a template, and it breaks the chart. Measured:

```
README.md     render: Error: YAML parse error on …/rbac-policies/README.md
              lint:   [ERROR] file extension '.md' not valid
_README.md    render: OK      (leading _ means Helm does not emit it)
              lint:   [ERROR] file extension '.md' not valid
_README.txt   render: OK      lint: OK
```

Two independent rules, and you need both: a **leading `_`** stops Helm emitting the file as a manifest,
and `helm lint` accepts only **`.yaml`, `.yml`, `.tpl`, `.txt`**. Hence
`templates/rbac-policies/_README.txt`. Ordinary documentation belongs outside `templates/` — which is why
this guide is in `working-sessions/docs/`.

---

## 7. The traps, collected

| trap | what happens | the fix |
|---|---|---|
| Guard not built as a string | Helm evaluates `hasSuffix` against an undefined `.Name`, renders the binding away, **no error** | build the whole `if` with `printf`, substitute it |
| `\| quote` on a deferred expression | operator's Go-template parse fails on `\"` inside an action | pass quotes as `printf` arguments |
| `{{ }}` inside a `#` comment | Helm evaluates it — `#` is YAML, not Helm | prose in `#`, or use `{{/* */}}` |
| Parsing an objectTemplate directly | YAML error on the guard line | render expressions out first |
| `.` inside `range` | root context lost; `include "nco.labels" .` gets the loop item | pass `$` |
| Editing labels and expecting propagation | GOTCHA 9 — `.metadata` is excluded, existing objects keep old metadata | delete the CRs, let it rebuild |
| `-l` on `source-namespaceconfig` | matches nothing on most policies (it is an annotation) | `-l rbac.ocp.io/config-source=…` |
| `--set` with a list index | can empty the whole list and trip a different guard | use `-f` with a temp values file |

---

## See also

- `working-sessions/docs/labels-and-annotations.md` — the label and annotation contract these templates
  implement
- the header comment in each of the four templates — the reasoning specific to that file
- `working-sessions/README.md` — GOTCHA 9 and the operator's behaviour in general
