# Review — chart 0.22.0, excludedPaths as the chart's policy (PR #24)

Adversarial second-opinion passes, 2026-09-05, on branch `feat/16-metadata-no-longer-excluded` (`git diff main..HEAD`):
templates 10-, 11-, 12-, 13- render `excludedPaths: [.status, .spec.replicas]`, values drop `.metadata`, Chart.yaml
0.22.0, the CI step, and the docs. Reviewers: Codex (gpt-5.6-sol, xhigh, read-only sandbox, ran `helm template`
and a three-way merge-patch probe in a copy) and Cursor (Grok 4.6 high fast, ask mode, traced from the templates,
the CRD and the operator's `EffectiveExcludedPaths`; no shell). Every verdict was re-measured here (`helm lint`,
`helm template`, the CI step run offline, `helm upgrade --dry-run=server` against the sandbox release). The design
itself was reviewed separately (operator repository, `docs/DESIGN_excludedPaths.md`; pointer in this repository's
`docs/DESIGN_excludedPaths.md`). Briefs and raw outputs: session scratchpad `adv/review_brief_chart022.md`,
`adv/review_codex_chart022_last.txt`, `adv/review_cursor_chart022.txt`.

## First pass (head 03fe6ed)

| Claim | Codex | Cursor | Decision |
|---|---|---|---|
| C1 stock values and crc-values render `[.status, .spec.replicas]` on every template and no other list | REFUTED (the oud-group extras path renders more) | CONFIRMED for the two named files | **Confirmed as stated for the two files** (Codex: 6 and 11 block-style lists, one unique tuple). The extras path is by design and is the subject of C2. |
| C2 an overlay that still lists `.metadata` renders it (set-once for that policy); nothing warns; the docs say what to do | REFUTED: nothing warns, docs silent; a guarded `fail` is warranted | REFUTED: same; `fail` in 12-, not NOTES (ArgoCD never prints NOTES) | **Accepted.** 12- now refuses `.metadata` in a policy's `excludedPaths` unless the policy sets `allowMetadataExcluded: true`; values.yaml documents the flag; the CI probe is a pair (refused without the flag, rendered with it, `.metadata` kept on bdp's two templates, the chart's policy on all 11 blocks). Measured: unacknowledged overlay refused at 12-:196 with the intended message; acknowledged overlay renders 11 blocks, 2 with `.metadata`. |
| C3 Helm three-way merge adds the list on the first upgrade and a later upgrade changes nothing; no path leaves `.metadata` behind | REFUTED: later upgrade is a no-op only while live matches and restores a drifted list; an old overlay is a path that keeps `.metadata` | REFUTED: same, plus `--reuse-values` carrying an old overlay | **Accepted as wording and as the C2 guard.** Chart.yaml, 10-'s header and the design pointer now say: first upgrade replaces the legacy list, a later upgrade is a no-op only while live still matches and restores it if drifted; the `.metadata` overlay is refused. Codex's merge-patch probe: `{}` when old/new/live agree, the rendered list when live drifted. |
| C4 ArgoCD: Git equals live in both directions, order included | CONFIRMED | CONFIRMED: Git order is the only cluster order; the operator's sorted union never touches the spec | — |
| C5 every sentence in Chart.yaml, headers and values describes implemented behaviour | REFUTED: the "only a release whose list differs rewrites it" sentence; 11-/13- "the operator's default"; labels doc §6 procedure; GOTCHA 9 prose | REFUTED: same list | **Accepted.** All rewritten (see the list below). |
| C6 the reference copies under `working-sessions/policies/` may keep `.metadata` | REFUTED: they claim to describe current intent; six entries in three files | REFUTED: the README's "compared line for line" contract | **Accepted.** The six entries now read `[.status, .spec.replicas]`; the stale header in `extra-groupconfig-rbac.helm-template.yaml` rewritten. Codex's parser finds no `.metadata` entry (measured). |

**Volunteered by both, accepted:** `NOTES.txt` and the chart README still told the installer to `oc apply -f policies/`
(the pre-chart-policy text; the opposite of the root README). Both now name what the chart deploys and say not to
apply the reference copies. Root README said "all of them default to off" in two places; values.yaml has the
baseline tiers and `clusterRbac` enabled (measured with PyYAML), so both now state which default on and which off.

**Stale text rewritten (C5):** Chart.yaml 0.22.0 entry; 10- header (Helm three-way merge sentence); 11- and 13-
comments; `working-sessions/docs/labels-and-annotations.md` §6 (delete-all-CRs procedure now scoped to older pairs);
`working-sessions/README.md` (operator "injects" and "every NamespaceConfig excludes .metadata");
`working-sessions/docs/templating-guide.md` trap table; `templates/rbac-policies/_README.txt`.

## Verification after the changes

- `helm lint` clean with values.yaml and with crc-values.yaml.
- Rendered NamespaceConfig and GroupConfig specs identical to head 03fe6ed for both values files (PyYAML compare);
  one unique list, `[.status, .spec.replicas]`.
- CI step run offline: unacknowledged overlay refused by 12-; acknowledged overlay 11 blocks, 0 missing
  `.spec.replicas`, `.metadata` kept on 2.
- `helm upgrade --dry-run=server` against the sandbox release: would become revision 11, 11 `excludedPaths` blocks;
  every live CR already carries `[.status, .spec.replicas]` (release 10).
- Codex's not-asked grep for the stale install text: no hits.
