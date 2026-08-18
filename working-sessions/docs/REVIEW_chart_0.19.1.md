# Review — chart 0.19.1 (branch `feat/oud-group-multiple-policies`)

**Reviewer: Fable 5. Arbiter: Claude.** Fable writes findings here. Claude accepts or rejects each one
against the use case below, and only ACCEPTED items get implemented.

## The use case, so a finding can be judged against it

A Helm chart installs the redhat-cop Namespace Configuration Operator via OLM **and** ships the RBAC
policies. Two template engines share `{{ }}`: Helm renders at install; the **operator** renders each
`objectTemplate` later, once per matching namespace or group, where `.Name` / `.Labels` are ITS context.
Operator expressions are therefore built as **strings** so Helm cannot evaluate them — if Helm does
evaluate one, it tests an undefined `.Name`, renders the object away, and **reports success**.

- Managed by ArgoCD eventually, so install and uninstall must be **one-shot and self-healing**.
- The 5 policy CRs are Helm's; the ~42 RoleBindings/ClusterRoleBindings/Roles are the **operator's** and
  have **no ownerReferences** — nothing garbage-collects them. Hence the orphan sweeper.
- The operator injects `excludedPaths: [.metadata, .status, .spec.replicas]`, so **metadata edits never
  reach objects that already exist**. Spec changes do propagate.
- `roleRef` is **immutable** in Kubernetes.
- Live cluster: CRC, release `nco`, rev 19, chart 0.19.1, 42 objects, 5 CRs.

**Constraints on any proposed fix — a finding that violates these is out of scope:**

1. **No clever design, no complicated logic.** Simplest thing that is correct.
2. **Never `| quote` a built operator expression** — the operator renders Go-template first, parses YAML
   second, so `\"` breaks the parse. Quotes go in as `printf` arguments.
3. **`#` is a YAML comment, not a Helm comment.** An action inside one IS evaluated.
4. **No heredocs and no column-0 closing quotes inside the sweeper script** — both end the enclosing
   YAML block scalar and break the ConfigMap.
5. **Nothing hardcoded in CI** that values.yaml owns (label keys, policy names, counts). Derive it.
6. **Comments say WHY, not WHAT.** Condensing must not delete the reasoning.
7. `/metrics`-style public-by-decision choices and the sweeper's broad ClusterRole are **accepted
   trade-offs**, already argued in the templates. Re-litigating them is not a finding.

## Files in scope

```
charts/namespace-configuration-operator/templates/14-orphan-sweeper-script.yaml   the sweeper (bash in a ConfigMap)
charts/namespace-configuration-operator/templates/15-orphan-sweeper-rbac.yaml     its SA + ClusterRole
charts/namespace-configuration-operator/templates/rbac-policies/10..13*.yaml      the four policies
charts/namespace-configuration-operator/values.yaml                               ~700 lines, mostly comment
working-sessions/scripts/check-ordering.py                                        the CI ordering check
working-sessions/docs/labels-and-annotations.md                                   the label contract
```

## Claims to verify — one verdict each: CONFIRMED / REFUTED / FIX-INADEQUATE

Prefer **refutation**. "Cannot refute" is fine only if you say what you actually checked.

**Sweeper (14, 15)** — 0.19.1 just fixed a bug where `! oc get role ... >/dev/null 2>&1` treated
*Forbidden* as *not found*, so a missing `get` verb made every managed RoleBinding look dangling and it
deleted all of them on every sync. Counts matched afterwards because the operator rebuilt them, so it
hid. With that in mind:

- **S1** Any REMAINING place in the script where a failure or empty result is read as a decision to
  delete, or as "nothing to do". Include the `IFS` juggling and the `while read` subshell counters.
- **S2** `ORPHAN_LIMIT` is checked for the first sweep only. Is the second sweep (dangling Roles)
  unbounded, and does that matter given it deletes only on a definite absence?
- **S3** The second sweep does one `oc get role` per binding. At 42 objects that is fine; state where it
  stops being fine and whether the simplest fix (one `oc get role -A` up front) is worth it.
- **S4** The ClusterRole now grants `get,list,delete` on roles/rolebindings/clusterrolebindings
  cluster-wide. Given constraint 7, is `get` on `roles` alone sufficient, or is anything now unused?
- **S5** `DRY_RUN=true` — verify BOTH sweeps genuinely delete nothing and still report what they would do.

**Policies (10–13)**

- **P1** Any operator expression Helm could evaluate, or any `| quote` on one.
- **P2** `12`'s `$group` comes from `index .Labels "<key>"`. What renders if a matching namespace lacks
  that label — an empty subject name, a rejected object, or a silent no-op? State which.
- **P3** Two `oudGroup.policies` keys sharing a `labelKey` or a `roleName`: what actually collides now
  that the duplicate guard was removed? (RoleBindings are per-namespace; Roles coexist.)

**Ordering check**

- **K1** A wave ordering that is wrong but PASSES: find one the four assertions miss.
- **K2** The source pass splits on `^---$` textually. Find a valid template shape it mis-parses.

**Comments and docs — the condensing pass**

- **D1** Name the specific comment blocks that state WHAT the code already says, or repeat a fact stated
  elsewhere, and give the condensed replacement text. Preserve every WHY, every measured number, and
  every trap. Say how many lines each saves.
- **D2** Any comment or doc line that is now **factually wrong** after 0.19.1 (especially anything
  implying Helm cannot override, or that a roleName change needs a manual step).

## Required form for every finding

````
> **Fable:** S1 — CONFIRMED
> **Where:** file:line or symbol
> **Trigger:** the concrete state or input, not "could race"
> **Consequence:** what a reader of `oc get` would believe that is false
> **Fix (complete, ready to apply):**
> ```bash
> # the whole replacement block, matching the surrounding comment style
> ```
> **Proof:** the command you ran and its output
````

Then Claude appends `**Claude: ACCEPT**` or `**Claude: REJECT** — reason`.

Findings must carry a **complete** replacement block, not "add a check". Measure rather than reason:
`helm lint`, `helm template`, `oc auth can-i --as=<sa>`, a scratch script. If you assert a behaviour,
show the command and its output.

---

## Fable — pass 1

_(Fable writes below this line.)_
