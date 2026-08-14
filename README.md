# Helm chart repository — openshift-rbac-automation

This branch is **generated**. Do not edit it by hand and do not commit chart packages here
yourself — `.github/workflows/helm.yaml` on `main` publishes them with
[chart-releaser](https://github.com/helm/chart-releaser-action), and a hand-pushed file will
either be overwritten or leave `index.yaml` disagreeing with what is actually here.

Chart source lives on `main` at `charts/namespace-configuration-operator/`.

## Use it

```bash
helm repo add openshift-rbac-automation https://ephico2real2.github.io/openshift-rbac-automation
helm repo update
helm search repo openshift-rbac-automation
```

## Why this branch was created by hand

chart-releaser with `packages_with_index: true` builds a git worktree from `origin/gh-pages`
and **cannot create the branch itself** — the first run against a repo without it fails with
`fatal: invalid reference: origin/gh-pages`. So the branch is bootstrapped once, empty, and
every commit after this one is machine-written.
