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
| C2 an overlay that still lists `.metadata` renders it (set-once for that policy); nothing warns; the docs say what to do | REFUTED: nothing warns, docs silent; a guarded `fail` is warranted | REFUTED: same; `fail` in 12-, not NOTES (ArgoCD never prints NOTES) | **Accepted.** 12- now refuses `.metadata` in a policy's `excludedPaths` unless the policy sets `allowMetadataExcluded: true`; values.yaml documents the flag; the CI probe is a pair (refused without the flag, rendered with it, `.metadata` kept on bdp's two templates, the chart's policy on all 11 blocks). Measured: unacknowledged overlay refused by 12-'s guard with the intended message; acknowledged overlay renders 11 blocks, 2 with `.metadata`. |
| C3 Helm three-way merge adds the list on the first upgrade and a later upgrade changes nothing; no path leaves `.metadata` behind | REFUTED: later upgrade is a no-op only while live matches and restores a drifted list; an old overlay is a path that keeps `.metadata` | REFUTED: same, plus `--reuse-values` carrying an old overlay | **Accepted as wording and as the C2 guard.** Chart.yaml, 10-'s header and the design pointer now say: first upgrade replaces the legacy list, a later upgrade is a no-op only while live still matches and restores it if drifted; the `.metadata` overlay is refused. Codex's merge-patch probe: `{}` when old/new/live agree, the rendered list when live drifted. |
| C4 ArgoCD: Git equals live in both directions, order included | CONFIRMED | CONFIRMED: Git order is the only cluster order; the operator's sorted union never touches the spec | — |
| C5 every sentence in Chart.yaml, headers and values describes implemented behaviour | REFUTED: the "only a release whose list differs rewrites it" sentence; 11-/13- "the operator's default"; labels doc §6 procedure; GOTCHA 9 prose | REFUTED: same list | **Accepted.** All rewritten (see the list below). |
| C6 the reference copies under `working-sessions/policies/` may keep `.metadata` | REFUTED: they claim to describe current intent; six entries in three files | REFUTED: the README's "compared line for line" contract | **Accepted.** The six entries now read `[.status, .spec.replicas]`; the stale header in `extra-groupconfig-rbac.helm-template.yaml` rewritten. Codex's parser finds no `.metadata` entry (measured). |

> **Correction from the second pass (head ba64c55):** the C3 decision above is wrong where it says a later upgrade
> "restores the rendered list if live has drifted". helm v3.14.0 computes a two-way JSON merge patch from the previous
> and the new rendered manifests for these CRs; an unchanged render is `{}` and Helm does not restore live drift.
> ArgoCD self-heal, `helm upgrade --force`, or a later change to `spec.templates` does. Details in the second-pass
> table below.

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

## Second pass (head ba64c55: the guard, the CI pair, the wording)

Brief `adv/review_brief_chart022_pass2.md`; outputs `adv/review_cursor_chart022p2.txt`, `adv/review_codex_chart022p2_last.txt`.

| Claim | Cursor | Decision |
|---|---|---|
| C1 the guard fires on `.metadata` for every non-"true" flag and not on bool/string true; null or absent extras unaffected; `.metadata.labels`/`.metadata.annotations` not caught | CONFIRMED, with the finding that the two subsets should be caught | **Accepted.** The guard now fires on `.metadata` and on any path under `.metadata.labels` or `.metadata.annotations`; `.metadata.finalizers` and other paths pass. Measured matrix: five paths × {absent, string "false", true} behave as intended; `.metadata.finalizers`, `.data` and no extras render. |
| C2 the CI step's shell branches behave as commented | REFUTED: the awk checked only `.spec.replicas` and skipped an empty block followed by a header; `blocks -gt 0` accepted any count | **Accepted.** Every block must carry both `.status` and `.spec.replicas` (closing on the next header too), exactly 11 blocks from crc-values, the refusals go through one helper that requires the guard's own message, the two subsets and a key under labels are probed, and `.metadata.finalizers` is the positive control. Cursor's counter-document yields missing=3 under the new awk (0 under the old). |
| C3 the Helm wording ("first upgrade replaces; a later upgrade is a no-op only while live matches and restores a drifted list") | PLAUSIBLE, source not fetchable | **Refuted here by the source, and my earlier wording retracted.** helm v3.14.0 `pkg/kube/client.go` `createPatch`: for an unstructured object (a CR) the patch is `jsonpatch.CreateMergePatch(oldManifest, newManifest)`, a two-way JSON merge patch between the previous and the new rendered manifests; the live object is fetched but used only on the strategic-merge path for typed objects; `updateResource` sends nothing when the patch is `{}` and replaces only under `--force`. So the first release that renders the list replaces the live one (consistent with release 8 to 10), and a later upgrade with an unchanged manifest sends nothing: a hand-edited live list is healed by ArgoCD (Git against live), not by Helm. Codex's first-pass "three-way merge-patch probe" modelled a function Helm does not use for CRs; the sentence I adopted from it was wrong. Chart.yaml, 10-'s header and the design pointer now state the measured behaviour. |
| C4 reference copies clean | CONFIRMED | — |
| C5 NOTES/README statement of which policies default on matches values.yaml | REFUTED as incomplete: Chart.yaml's description and the chart README named only the enabled half | **Accepted.** Both name the disabled half too; Cursor's PyYAML assertion passes. |
| C6 remaining current-tense stale statements | CONFIRMED: none; historical entries listed | — (`working-sessions/docs/REVIEW_chart_0.19.1.md` is a dated record and stays) |

**Volunteered by Cursor, accepted:** `crc-values.yaml` said values.yaml ships every policy off; it now names the
defaults it overrides.

**Verification after the second-pass changes:** lint clean (both values files); rendered CR specs identical to
head 03fe6ed (PyYAML); CI step offline (at 32f4d7b): five refusals by the guard, `.metadata.finalizers` renders, 11 blocks,
0 missing; NOTES renders on `helm install --dry-run`.

### Codex, second pass (reviewed at ba64c55; the branch had moved to 32f4d7b while it ran)

| Claim | Codex | Decision |
|---|---|---|
| C1 | CONFIRMED, with the same finding as Cursor: guard `.metadata.labels`/`.metadata.annotations` and descendants, keep `.metadata.finalizers` allowed | already in 32f4d7b; Codex's regression passes |
| C2 | REFUTED: the CI grep for `allowMetadataExcluded: true` could be satisfied by another `fail` whose text carries a user-controlled label value; the awk missed a block open at EOF and checked only `.spec.replicas`; `blocks -gt 0` did not enforce 11 | **Accepted the marker.** The guard message starts with `E_METADATA_EXCLUDED_UNACKNOWLEDGED:` and CI greps for that token with `-F`; a string "yes" probe added. The awk and block count were already fixed in 32f4d7b. |
| C3 | REFUTED from the source, the same finding as this record's own measurement: `createPatch` uses `jsonpatch.CreateMergePatch(oldData, newData)` for unstructured objects; `--reuse-values` carries an old overlay forward (now refused by the guard) | wording already corrected in 32f4d7b; erratum added under the first-pass table |
| C4 | CONFIRMED (PyYAML: 12 CRs, 6 explicit blocks, 0 `.metadata`) | — |
| C5 | REFUTED as incomplete, same as Cursor | already in 32f4d7b |
| C6 | CONFIRMED | — |

**Volunteered by Codex, accepted after measuring against values.yaml:** the chart README's `subscription.resources`
default read 250m/500Mi to 2/4Gi; values.yaml has 100m/128Mi to 500m/512Mi. The root README said unrecognised
environments "default to audit-only"; template 10's selector is an `In` allow-list over the declared environments,
so an unrecognised one receives nothing.

## Third pass (head 679dfc4: the subset guard, the marker, the corrected Helm wording)

Brief `adv/review_brief_chart022_pass3.md`; outputs `adv/review_cursor_chart022p3.txt`, `adv/review_codex_chart022p3_last.txt`.

| Claim | Cursor | Decision |
|---|---|---|
| C1 the guard's `range`/`toString` cannot panic or be bypassed by a non-string entry; no legitimate metadata path is wrongly caught | CONFIRMED (sprig `strval` stringifies numbers, maps and nil; ObjectMeta has no field starting `labels`/`annotations` other than the two) | — |
| C2 every Helm sentence is true of v3.14.0 | CONFIRMED with two overstatements: "the live object is not consulted" (it is fetched, then unused on the CR path) and "healed by ArgoCD" unconditionally (only with selfHeal, which this repository's Application sets) | **Accepted both**; Chart.yaml and the design pointer now say so. |
| C3 `refused_by_guard` exits 1 on a refusal by another fail | REFUTED: the marker was grepped anywhere, and 12-'s groupPrefix fail prints the user's value with `%q`, so `--set groupPrefix='*E_METADATA_EXCLUDED_UNACKNOWLEDGED:'` satisfied the helper (measured here: it did) | **Accepted, with a different fix than the proposed token blacklist:** the match is anchored to Helm's error line, `^Error: execution error at ([^)]*12-custom-oud-group[^)]*): E_METADATA_EXCLUDED_UNACKNOWLEDGED: `, so the marker must follow the template location, where no user value can appear. Measured: the forged value no longer matches; the six probes still pass. |
| C4 every decision row matches HEAD; the verification numbers match a render | CONFIRMED by construction (11 = 3 + 3 + 4 + 1), noting "five refusals" (now six) and a stale line number in the first-pass table | **Accepted**; both corrected. |
| C5 rendered CR specs identical to 03fe6ed | PLAUSIBLE (no shell) | **Confirmed here** (PyYAML). The two baseline CRs' `description` annotation changes on purpose, see C6. |
| C6 remaining statements that mismatch values.yaml | six found: the baseline `description` values (rendered onto the live CRs) and the root README's environment table, bullets, expected RoleBindings and allow-list line still described admin in nonprod and developer in prod, while values grant developer+audit in nonprod and audit only in prod; the chart README called the Namespace a pre-install hook (it is an ordinary resource) and listed `createNamespace` as `true` (values: `false`) | **Accepted all six after measuring each against values.yaml and the templates.** |

**Verification after the third-pass changes:** lint clean (both values files); rendered CR specs identical to 03fe6ed,
the two `description` annotations changed as intended; CI step offline: six refusals by the guard, the forged
groupPrefix value not matched, `.metadata.finalizers` renders, 11 blocks, 0 missing.

### Codex, third pass (reviewed at 679dfc4; the branch had moved to 0a1afd3 while it ran)

| Claim | Codex | Decision |
|---|---|---|
| C1 | CONFIRMED (Helm 3.14.0 runs: numbers, maps and nulls in the list neither panic nor hide a sibling `.metadata`; `.metadata.labelsX` caught, no ObjectMeta field wrongly caught) | — |
| C2 | REFUTED: "live not consulted" overstated (fetched, unused on the CR path); "until the manifest changes again" too broad (a metadata-only render carries no `excludedPaths`; a `spec.templates` change carries the whole array) | **Accepted.** 10-'s header and Chart.yaml corrected (0a1afd3 had fixed Chart.yaml and the pointer for the first point). |
| C3 | REFUTED with the same forged-marker finding as Cursor, via `labelKey` | already fixed in 0a1afd3 (anchored match); Codex re-ran that step: six refusals pass, forged refused. |
| C4 | REFUTED as of 679dfc4: the second-pass C2 cell said the helper "requires the guard's own message", which the forgery disproved | **Accepted**: the third-pass table records the forgery and the anchored fix; the numbers (11, 2, 0) confirmed by Codex's PyYAML run. |
| C5 | CONFIRMED (PyYAML over `git archive` copies of 03fe6ed and HEAD: specs equal for both values files) | — |
| C6 | REFUTED: a further list of statements contradicting values.yaml | **Accepted after measuring each:** chart README `operatorImage.enabled` and `reconcile.enabled` rows said `false` (values: `true`) and the override section told users to enable what is on; root README: the "tighten prod" paragraph removed a developer role prod does not have, the install sentence said the chart creates the namespace (`createNamespace: false`), the "everything" command lacked the bdp leaf flag, three sections presented a user-workload-monitoring policy the chart does not deploy (render: zero such objects; the reference policy is parked), the cluster-developer examples said `view` (values bind `edit`), the tree comment said all flags ship disabled, and the verification section expected admin RoleBindings the baseline never creates; values.yaml and 10- still described a two-step first install (the chart vendors 2 CRDs; values:349 already said one command) and values said the baseline binds admin/edit/view (edit and view). |

**Volunteered by Codex, accepted:** the two-step-install comment in template 10 (same correction).
