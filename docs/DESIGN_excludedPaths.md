# Design pointer — excludedPaths: the chart's part of the decision

The design review (2026-09-05, Codex, Cursor and a first-principles Fable 5.1 reviewer, both options, six claims
each) and its decisions are recorded in the operator repository, `docs/DESIGN_excludedPaths.md` on the
namespace-configuration-operator fork. The chart's part:

- The operator (from the build that applies its defaults in memory) never writes `spec.templates[].excludedPaths`.
  The list on a CR is its author's; here, the chart's.
- This chart declares `[.status, .spec.replicas]` on every template as its own policy (10-, 11-, 12-, 13-). That is
  not a mirror of the operator's defaults (which changed twice in a day and now include `.metadata.finalizers`);
  the operator unions its defaults with the declared list in memory, so a difference cannot loop or hide anything.
- Declaring the list is what migrates existing clusters off the `.metadata` the old operator wrote into every CR:
  only a Helm release whose rendered list differs from the previous one rewrites it (measured on the sandbox,
  release 8 to 10). CRs outside the chart are named by the operator's `MetadataExcluded` Warning event.
- Ordering: the operator image first, then chart 0.22.0. Against an older operator a declared list that differs
  from its defaults is the 0.21.1 rewrite loop under ArgoCD self-heal.
- Rejected: the operator removing `.metadata` automatically (nothing can attribute an entry to the author or to the
  old operator: `spec.templates` is one atomic value to every writer), and a status field for the effective list
  (a CRD change OLM owns and this chart duplicates).
