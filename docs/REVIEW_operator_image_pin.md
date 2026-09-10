# Adversarial review — operator image pin (chart 0.23.0)

Reviewed: `3230038` in this repo and `bf62dda` in the `namespace-configuration-operator` fork.
Fixes: `44601a7` here, `167e2b5` there.

| Reviewer | Invocation | Verified |
|---|---|---|
| Codex | `codex exec -m gpt-5.6-sol -c model_reasoning_effort="xhigh"` | session jsonl records `"model":"gpt-5.6-sol"`, `reasoning_effort":"xhigh"` |
| Cursor | `cursor agent -p --mode ask --model cursor-grok-4.6-high-fast` | probe returned the expected token before launch |

Cursor stated up front that ask mode blocked every shell invocation, so its verdicts are read from
source. Codex had a shell and executed the script, the render matrix and the CI gate bodies.

## Claims

| # | Subject | Codex | Cursor | Decision |
|---|---|---|---|---|
| C1 | helper resolves digest > tag > appVersion, refuses bad input | REFUTED | REFUTED | accepted on the fact, snippet rejected |
| C2 | `toString` blocks float coercion | REFUTED | CONFIRMED (tag) | accepted on the fact, folded into C1 |
| C3 | image/policy/secret patched independently, valid JSON | CONFIRMED | CONFIRMED | no change |
| C4 | `expectedImagePattern` still gates the image only | CONFIRMED | CONFIRMED | no change |
| C5 | rollback unaffected by the restructure | REFUTED | REFUTED | **accepted — a regression** |
| C6 | digest flows through `repo_of` and rollback | CONFIRMED | CONFIRMED | no change |
| C7 | tag legal as a Docker tag and a label value | CONFIRMED | CONFIRMED | no change |
| C8 | both CI gates fail for all four mutants | CONFIRMED | REFUTED | no change; coverage holds across the pair |
| C9 | chart version bumped, appVersion unchanged | CONFIRMED | CONFIRMED | no change |
| C10 | OFF state renders nothing | CONFIRMED | CONFIRMED | no change |
| C11 | fork `master` trigger correct, `:latest` still manual | REFUTED | CONFIRMED | **accepted — tags not enforced immutable** |
| C12 | upgrade path is one rollout then no-ops | PLAUSIBLE | PLAUSIBLE | no change; cluster-only |
| N1 | propagation wait ignores the pull policy | — | PLAUSIBLE | **accepted** |
| N2 | `imagePullSecrets` replaces the whole array | — | PLAUSIBLE | rejected — pre-existing |

## C5 — the regression this pass existed to find

**Finding.** Reconciling fields independently created a policy-only patch path. It reaches section 5
with `CURRENT = TARGET_IMAGE`, and the guard there keyed on the image, so it took the "no previous
value to roll back to" branch — blaming an image nobody touched, never reaching the Deployment patch,
and leaving the new pull policy on a wedged install.

**Re-check.** Codex executed sections 3–5 with a mocked `oc` and reproduced it. I reproduced it
independently against the committed script: 0 Deployment patches, 0 CSV reverts. After the fix, 1 of
each, restoring `imagePullPolicy: Always`.

**Decision.** Accepted. The guard now keys on `OPS` (empty = this run changed nothing) and the revert
restores every field the run patched. Cursor's `rolled` flag with duplicated branches was rejected as
more structure than the hole needs; one strategic-merge Deployment patch matches the container by
name and carries both fields.

## N1 — the same defect one layer down

**Finding.** The propagation wait compared the live image only, so on a cluster already at the pin a
policy-only patch matched on the first poll and `oc rollout status` passed on the old revision. The
live Deployment could keep the old policy forever while the CSV read the new one, after which the
CronJob compares the CSV, sees a match, and skips.

**Decision.** Accepted. The existing loop waits on both fields — three added lines, rather than the
second wait loop proposed.

## C1/C2 — accepted on the fact, snippets rejected

Codex measured `empty_repository rc=0 TARGET_IMAGE=:v1.2.6-142-ga8b0ea9` and
`%!s(float64=1.3):...` for a float repository — both non-empty, so `${TARGET_IMAGE:?}` never fires.
The helper now refuses an empty repository and a non-Docker tag. Cursor's repository-path regex was
rejected: it would refuse `localhost:5000/x` and other legitimate forms.

## C11 — Cursor confirmed it, Codex refuted it

Codex was right. `git describe` is commit-derived, so a rerun recomputes the same tag names while
`BUILD_DATE` changes the digest, and the push moved a tag a consumer pins. A `docker manifest inspect`
check before the push now fails the run. Codex's new script + test + concurrency block was rejected as
more machinery than the hole needs.

## Retracted

**S1, mine.** I claimed the CI gate's `exit 1` was lost in a pipeline subshell. Both reviewers refuted
it and a faithful retest agrees: the pipeline is the step's last command, so the step inherits the
subshell's status with or without `-e`. My original test had a trailing `echo` the real step does not
have — that, not the subshell, produced the exit 0.

## Outcome

Four findings accepted, two rejected, one of my own retracted. The two that mattered — C5 and N1 —
were both the same shape as the bug the PR set out to fix: a comparison that cannot observe the thing
that changed. C11 is that shape again, in the registry. Full validation re-run green after the fixes.
