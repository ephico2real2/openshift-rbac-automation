# `templates/rbac-policies/` — the RBAC policies

**This is the directory to edit when you are adding or changing an access policy.** Everything in
`templates/` above this folder installs and maintains the *operator* — namespace, OperatorGroup,
Subscription, the CSV image override, the InstallPlan approver. Touching those changes how the operator
runs. Touching these changes **who has access to what**.

| file | CRD | grants | emits | CR name it creates |
|---|---|---|---|---|
| `10-baseline-namespaceconfig-rbac.yaml` | NamespaceConfig | the baseline every team gets, per namespace — nonprod and prod | RoleBindings | `baseline-nonprod-rbac`, `baseline-prod-rbac` |
| `11-baseline-groupconfig-rbac.yaml` | GroupConfig | the baseline cluster-wide tiers | ClusterRoleBindings | `baseline-cluster-rbac` |
| `12-custom-oud-group-namespaceconfig-rbac.yaml` | NamespaceConfig | a bespoke submitter Role, per namespace | Role + RoleBinding | `abc-oud-group-rbac` |
| `13-custom-groupconfig-rbac.yaml` | GroupConfig | ClusterRoles we define, bound by group-name suffix | ClusterRoleBindings or RoleBindings | `custom-cluster-rbac` |

## The FILENAME names the CRD. The CR NAME names the family and scope.

Two different jobs, deliberately not the same string:

- **The filename keeps `namespaceconfig` / `groupconfig`** so anyone opening this directory sees which
  CRD a template handles without reading it. That is not cosmetic: a NamespaceConfig is keyed on a
  NAMESPACE and emits RoleBindings, a GroupConfig is keyed on a GROUP and emits ClusterRoleBindings, and
  inside an objectTemplate `.Name` therefore means a different thing in each. It is the first fact you
  need and the last one you should have to go hunting for.
- **The CR name drops it**, because `kind:` on the object and the `rbac.ocp.io/kind` label already state
  it. What a CR name has to answer is *which policy is this* while you are looking at a binding's
  provenance on a cluster — hence `<family>-<scope>-rbac`, which lines up with the
  `rbac.ocp.io/config-source` label values (`nonprod-rbac`, `prod-rbac`, `cluster-rbac`, …).

So renaming a CR is a values change and never touches these filenames. Helm ignores template filenames
entirely; the numbering is a reading order for humans and nothing more.

**As of 0.9.0 these ship ENABLED** — `namespaceConfigPolicy`, its `baseline` and `oudGroup` children, and
`clusterRbac` all default to true; only `customGroupConfig` is still off. Installing this chart therefore
writes RBAC against any namespace or group matching the selectors. For the operator alone, set
`namespaceConfigPolicy.enabled=false` and `clusterRbac.enabled=false` explicitly.

## Helm renders subdirectories — this folder is not special to Helm

Helm walks `templates/` **recursively**, so a file here is rendered exactly as it would be one level up.
Verified when this folder was introduced: the rendered output before and after the move was byte-identical
apart from the `# Source:` path comment — 1749 lines and 18 resources both ways.

Three consequences worth knowing:

- **`_helpers.tpl` still works from here.** A chart has ONE template namespace regardless of file layout,
  so `include "nco.labels"` resolves even though the helper sits in the parent directory.
- **Filenames and the `10`–`13` prefixes do not control anything.** Helm's install order is by resource
  **kind**, not by path; within a kind it falls back to name. The numbers are a reading order for humans,
  and the actual apply ordering for ArgoCD comes from `argocd.argoproj.io/sync-wave: "3"` on each CR.
  Renaming or renumbering a file is cosmetic.
- **EVERY file here is rendered, so a plain document breaks the chart.** This file is
  `_README.txt`, and both parts of that name are load-bearing. Measured while adding it:

  ```
  README.md    render: Error: YAML parse error on …/rbac-policies/README.md
               lint:   [ERROR] file extension '.md' not valid
  _README.md   render: OK          (a leading _ means Helm does not emit it)
               lint:   [ERROR] file extension '.md' not valid
  _README.txt  render: OK          lint: OK
  ```

  So: a leading `_` stops Helm emitting the file as a manifest, and `.txt` is one of the four
  extensions `helm lint` accepts (`.yaml`, `.yml`, `.tpl`, `.txt`). Drop a `.md` in here and CI fails.
  Put ordinary documentation outside `templates/`.

## Before you edit

1. **Read the header of the file you are changing.** Each one documents why it is shaped the way it is,
   and the traps specific to it. They are long on purpose.
2. **These templates contain expressions meant for the OPERATOR, not for Helm.** They are built as
   *strings* so Helm cannot evaluate them. If you do not know why, read
   `working-sessions/docs/templating-guide.md` first — the failure mode is silent: Helm evaluates the
   guard against an undefined value and renders your binding away with no error.
3. **A `#` comment is NOT a Helm comment.** An action inside one IS evaluated.
4. **Labels and annotations are a fixed contract**, not free-form. See
   `working-sessions/docs/labels-and-annotations.md` — there is a checklist for a new policy in §7.
5. **Same shape → add to `values.yaml`. Different shape → its own numbered file.** `10-baseline-` holds
   two policies because nonprod and prod differ only in data. `12-custom-oud-group-` is separate because
   it differs structurally. Do not add an `if` to serve a structurally different policy.

## After you edit

```sh
helm lint chart
helm template t chart --set namespaceConfigPolicy.enabled=true …    # see the guide for the full flag set
```

**An `objectTemplate` is not valid YAML until it is rendered** — do not hand one to a YAML parser. Render
the operator's expressions out first; `working-sessions/docs/templating-guide.md` §5 has the script.

And if you changed a label or annotation, remember it will **not** reach objects that already exist — the
operator excludes `.metadata` from comparison. The CRs must be deleted and rebuilt, which is a real
revocation window (~4s to revoke 55 objects, ~50s to restore).
