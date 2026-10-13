#!/usr/bin/env bash
# Renders the developer onboarding guide and checklist from their sources, filling in the label domain from
# onboarding.env, so the domain is written in one place. Writes docs/ONBOARDING.md and docs/ONBOARDING_CHECKLIST.md.
# Runs the same on macOS (BSD sed) and Linux (GNU sed): only `sed -e` with a plain substitution is used.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
docs=$(dirname "${here}")

# Read the one value without sourcing the file, so the env file cannot run anything.
LABEL_DOMAIN=$(sed -n -e 's/^LABEL_DOMAIN=//p' "${here}/onboarding.env" | tail -n 1)

# A label key's prefix must be a lowercase DNS subdomain of at most 253 characters (Kubernetes IsDNS1123Subdomain), or
# the API refuses the label; anything else would also break the substitution below.
if ! [[ "${LABEL_DOMAIN}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$ ]] \
  || [ "${#LABEL_DOMAIN}" -gt 253 ]; then
  echo "render.sh: LABEL_DOMAIN in ${here}/onboarding.env must be a lowercase DNS name, got '${LABEL_DOMAIN}'" >&2
  exit 1
fi

for name in ONBOARDING ONBOARDING_CHECKLIST; do
  src="${here}/${name}.md.in"
  out="${docs}/${name}.md"
  {
    printf '%s\n\n' "<!-- Generated from docs/onboarding/${name}.md.in by docs/onboarding/render.sh: edit the source, not this file. -->"
    sed -e "s|@LABEL_DOMAIN@|${LABEL_DOMAIN}|g" "${src}"
  } > "${out}.tmp"
  # Every placeholder must have been filled; a leftover, or half of one, means a misspelled one in the source.
  if grep -n -E '@[A-Z_]{2,}|[A-Z_]{2,}@' "${out}.tmp" >&2; then
    rm -f -- "${out}.tmp"
    echo "render.sh: unfilled placeholder in ${src} (lines above)" >&2
    exit 1
  fi
  mv -- "${out}.tmp" "${out}"
  echo "rendered ${out#"${docs}/"} (label domain ${LABEL_DOMAIN})"
done
