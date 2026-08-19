#!/usr/bin/env bash
# Refresh the CRDs vendored under charts/namespace-configuration-operator/crds/ from a live cluster.
#
# WHY THEY ARE VENDORED AT ALL: Helm resolves every kind against API discovery before it applies
# anything, so a chart whose manifest contains NamespaceConfig/GroupConfig cannot install onto a cluster
# that does not serve those kinds yet. crds/ is applied before templates render, which is early enough,
# and it is the only mechanism Helm offers. Full reasoning and the measured evidence are in the header of
# each generated file.
#
# WHY THIS IS A SCRIPT AND NOT A ONE-LINER: a hand-copied CRD carries the cluster it came from — OLM's
# olm.managed label, its operators.coreos.com/* labels, the installed-alongside annotations, plus uid,
# resourceVersion, creationTimestamp and status. Committing those makes the file look like it belongs to
# one install, and re-applying them elsewhere is at best noise. This strips exactly that set and nothing
# else, so a refresh is reviewable as a schema diff rather than a diff of somebody's cluster metadata.
#
# WHEN TO RUN IT: when subscription.startingCSV is bumped to a version whose CRD schema changed. Not on a
# routine cadence — a stale copy here is self-correcting, because on a bare cluster Helm creates it and
# then OLM reconciles the CRD to the bundle's own version moments later.
#
# Usage:
#   working-sessions/scripts/refresh-vendored-crds.sh            # against the current oc context
#   working-sessions/scripts/refresh-vendored-crds.sh --check    # exit 1 if the committed files differ
#
# The --check form is what CI would call: it regenerates into a temp dir and diffs, so it needs a cluster
# with the pinned CSV installed. There is deliberately no offline check — nothing offline can tell you
# whether the vendored schema still matches the operator's.

set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../charts/namespace-configuration-operator" && pwd)"
CRD_DIR="${CHART_DIR}/crds"
GENERATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vendor-crd.py"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# DERIVED, NOT LISTED. The kinds to vendor are exactly the kinds the chart's own templates declare, so a
# new policy kind is picked up the day it is added rather than the day someone remembers this script.
# `helm template` is used rather than a grep, because the kind can come from a helper or a loop.
mapfile -t KINDS < <(
  helm template vendor-crd-probe "${CHART_DIR}" \
    | awk '/^apiVersion: redhatcop\.redhat\.io\//{group=1} /^kind: /{if (group) {print tolower($2); group=0}}' \
    | sort -u
)

if [ "${#KINDS[@]}" -eq 0 ]; then
  echo "::error::no redhatcop.redhat.io kinds render from this chart — either the policies are all" >&2
  echo "         disabled in values.yaml or the API group changed. Refusing to write an empty crds/." >&2
  exit 1
fi

# Plural is the CRD name, and pluralising in shell is a trap. Ask the cluster instead: it knows the
# mapping between a kind and the CRD that defines it.
CRD_NAMES=()
for kind in "${KINDS[@]}"; do
  name="$(oc get crd -o jsonpath="{range .items[?(@.spec.group=='redhatcop.redhat.io')]}{.spec.names.singular}{' '}{.metadata.name}{'\n'}{end}" \
            | awk -v k="${kind}" '$1 == k {print $2}')"
  if [ -z "${name}" ]; then
    echo "::error::the chart renders kind '${kind}' but no CRD on this cluster defines it." >&2
    echo "         Install the operator first — this script reads the schema from a live cluster." >&2
    exit 1
  fi
  CRD_NAMES+=("${name}")
done

TARGET="${CRD_DIR}"
if [ "${CHECK}" = 1 ]; then
  TARGET="$(mktemp -d)"
  trap 'rm -rf "${TARGET}"' EXIT
fi

CSV="$(python3 -c "import yaml;print(yaml.safe_load(open('${CHART_DIR}/values.yaml'))['subscription']['startingCSV'])")"
INSTALLED="$(oc get csv -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
             | grep '^namespace-configuration-operator\.' | sort -u | head -1)"
if [ "${INSTALLED}" != "${CSV}" ]; then
  echo "WARNING: values.yaml pins ${CSV} but this cluster runs '${INSTALLED:-<none>}'." >&2
  echo "         The vendored schema would come from the CLUSTER, not the pin. Aborting." >&2
  exit 1
fi

mkdir -p "${TARGET}"
for name in "${CRD_NAMES[@]}"; do
  python3 "${GENERATOR}" --crd "${name}" --csv "${CSV}" --out "${TARGET}/${name}.yaml"
  echo "  ${name}.yaml"
done

if [ "${CHECK}" = 1 ]; then
  if diff -ru "${CRD_DIR}" "${TARGET}" >/dev/null 2>&1; then
    echo "OK: vendored CRDs match ${CSV} on this cluster."
  else
    echo "::error::the vendored CRDs differ from ${CSV} on this cluster:" >&2
    diff -ru "${CRD_DIR}" "${TARGET}" >&2 || true
    exit 1
  fi
fi
