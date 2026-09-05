#!/usr/bin/env bash
# Proves working-sessions/policies/kyverno-restrict-nco-writers.yaml on the current cluster, and its
# companion vap-protect-kyverno-configuration.yaml when it is applied.
#
# `oc auth can-i` cannot do this: it asks the authorization layer, and admission runs after
# authorization, so an edit holder gets "yes" whatever the policy says. This script instead
# performs the writes an identity would perform, impersonated and with --dry-run=server, which
# runs admission without persisting anything. Each identity is checked for a CREATE (a name
# that does not exist), an UPDATE (a label added to an existing probe object) and a DELETE of
# that probe. The three are separate requests on purpose: an `apply` of an existing, unchanged
# object is an UPDATE, not a CREATE, and would test the wrong operation.
#
# The expectation depends on the mode the policy is in on the cluster: in Deny a refused
# identity must see "denied the request"; in Audit it must succeed and the policy must have
# recorded a violation event. The script reads the mode from the cluster, never assumes it.
#
# Usage: working-sessions/scripts/verify-nco-writer-policy.sh
# Needs: a cluster-admin login (impersonation), the policy applied, jq.
set -euo pipefail

policy=restrict-nco-config-writers
probe=nco-writer-policy-probe
pass=0
fail=0

say()  { printf '%s\n' "$*"; }
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

mode=$(oc get validatingpolicy "$policy" -o jsonpath='{.spec.validationActions[*]}' 2>/dev/null) \
  || { say "policy $policy is not on this cluster; apply working-sessions/policies/kyverno-restrict-nco-writers.yaml first"; exit 1; }
case $mode in
  *Deny*)  enforcing=true ;;
  *)       enforcing=false ;;
esac
say "policy $policy: validationActions=[$mode] enforcing=$enforcing"

manifest=$(mktemp)
trap 'rm -f "$manifest"; oc delete namespaceconfig "$probe" --ignore-not-found >/dev/null 2>&1 || true' EXIT
probe_manifest() {
  cat <<EOF
apiVersion: redhatcop.redhat.io/v1alpha1
kind: NamespaceConfig
metadata:
  name: $1
spec:
  labelSelector:
    matchLabels:
      $probe: "true"
  templates: []
EOF
}
probe_manifest "$probe-create" >"$manifest"

# The UPDATE and DELETE probes need an object to exist; with no templates the operator adds no
# finalizer, so it is inert and removable. Created as the caller (a cluster-admin): if that is
# refused, the caller is not on the allow-list and nothing else can be tested.
probe_manifest "$probe" | oc apply -f - >/dev/null \
  || { say "the current login ($(oc whoami)) may not create a NamespaceConfig; run this as a cluster-admin"; exit 1; }

# classify <command...>: prints allowed | denied | forbidden | error(<text>)
classify() {
  local out
  if out=$("$@" 2>&1); then
    printf 'allowed'
  elif printf '%s' "$out" | grep -q 'denied the request'; then
    printf 'denied'
  elif printf '%s' "$out" | grep -qi 'forbidden'; then
    printf 'forbidden'
  else
    printf 'error(%s)' "$(printf '%s' "$out" | tail -1)"
  fi
}

# check <label> <expected: allow|deny> <impersonation flags...>
# "allow" must be allowed in both modes. "deny" must be denied in Deny mode and allowed in
# Audit mode (RBAC permitting: an identity RBAC forbids never reaches the policy, which is
# reported as such and counts as neither).
check() {
  local label=$1 expected=$2; shift 2
  local create update delete
  create=$(classify oc apply --dry-run=server -f "$manifest" "$@")
  update=$(classify oc label namespaceconfig "$probe" "$probe=touched" --overwrite --dry-run=server "$@")
  delete=$(classify oc delete namespaceconfig "$probe" --dry-run=server "$@")
  for op in create update delete; do
    local got; got=$(eval "printf '%s' \"\$$op\"")
    case "$expected:$enforcing:$got" in
      allow:*:allowed)        ok  "$label $op: allowed" ;;
      deny:true:denied)       ok  "$label $op: denied by the policy" ;;
      deny:false:allowed)     ok  "$label $op: allowed (Audit mode)"; audit_expected=$((audit_expected + 1)) ;;
      *:*:forbidden)          say "  info  $label $op: RBAC forbids this identity before admission" ;;
      *)                      bad "$label $op: expected $expected (enforcing=$enforcing), got $got" ;;
    esac
  done
}

audit_expected=0
run_started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
say "identities:"
check "edit holder (cluster-developer tier)"  deny  --as=probe-dev --as-group=app-ocp-rbac-alpha-cluster-developer --as-group=system:authenticated
# the tier exemption is the chart's family pattern; a -cluster-admin suffix from another family must not pass
check "edit holder plus evil-cluster-admin"   deny  --as=probe-evil --as-group=app-ocp-rbac-alpha-cluster-developer --as-group=evil-cluster-admin --as-group=system:authenticated
check "plain authenticated user"              deny  --as=probe-user --as-group=system:authenticated
check "cluster-admin tier group"              allow --as=probe-admin --as-group=app-ocp-rbac-alpha-cluster-admin --as-group=system:authenticated
check "kube:admin shape (system:cluster-admins)" allow --as=kube:admin --as-group=system:cluster-admins --as-group=system:authenticated
check "system:admin by name only (sudoer)"    allow --as=system:admin
check "system:masters certificate shape"      allow --as=probe-cert --as-group=system:masters
# login_groups: the current login's groups, from the API server itself (a SelfSubjectReview), as
# --as-group flags. Impersonating a name alone carries no groups, which would refuse a login that is
# cluster-admin only through a group (kube:admin via system:cluster-admins).
login_groups() {
  printf '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
    | oc create -f - -o json 2>/dev/null \
    | jq -r '.status.userInfo.groups[]? | "--as-group=" + .'
}
# shellcheck disable=SC2046  # one flag per group; group names carry no spaces
check "current login with its groups"          allow --as="$(oc whoami)" $(login_groups)
check "group-sync operator service account"    allow --as=system:serviceaccount:group-sync-operator:controller-manager
check "operator service account"              allow --as=system:serviceaccount:namespace-configuration-operator:controller-manager
check "GitOps application controller"         allow --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller

# In Audit mode every refused write must have produced a PolicyViolation event naming the policy;
# Kyverno emits them asynchronously, so allow a few seconds. Timestamps are cut to whole seconds
# before comparing: an eventTime with a fraction ("...:05.123456Z") sorts BELOW "...:05Z" as text
# (review). A failed `oc get events` counts as no events rather than ending the script.
if [ "$enforcing" = false ] && [ "$audit_expected" -gt 0 ]; then
  found=0
  for _ in 1 2 3 4 5 6; do
    json=$(oc get events -A --field-selector reason=PolicyViolation -o json 2>/dev/null) || json='{"items":[]}'
    found=$(printf '%s' "$json" | jq -r --arg p "$policy" --arg since "$run_started" '
      def zulu: if type != "string" or . == "" then empty else .[0:19] + "Z" end;
      [ (.items // [])[]
        | select((.message | type == "string") and (.message | contains($p)))
        | ((.eventTime // .lastTimestamp) | zulu) as $t
        | select($t >= $since)
      ] | length') || found=0
    case $found in ''|*[!0-9]*) found=0 ;; esac
    [ "$found" -ge "$audit_expected" ] && break
    sleep 2
  done
  if [ "$found" -ge "$audit_expected" ]; then
    ok "Audit mode recorded $found PolicyViolation events for the $audit_expected refused writes"
  else
    bad "Audit mode: expected $audit_expected PolicyViolation events naming $policy since $run_started, found $found"
  fi
fi

# The companion ValidatingAdmissionPolicy: the edit tier must not be able to change Kyverno's own
# configuration (a server dry run; nothing is written). Skipped with a note when it is not applied.
if oc get validatingadmissionpolicy protect-kyverno-configuration >/dev/null 2>&1; then
  got=$(classify oc patch cm kyverno -n kyverno --type=merge -p '{"data":{"verify-probe":"x"}}' --dry-run=server --as=probe-dev --as-group=app-ocp-rbac-alpha-cluster-developer --as-group=system:authenticated)
  case $got in
    *ValidatingAdmissionPolicy*|denied) ok "companion: the edit tier cannot change Kyverno's ConfigMap" ;;
    *) bad "companion: expected the edit tier to be refused on Kyverno's ConfigMap, got $got" ;;
  esac
  # shellcheck disable=SC2046
  got=$(classify oc patch cm kyverno -n kyverno --type=merge -p '{"data":{"verify-probe":"x"}}' --dry-run=server --as="$(oc whoami)" $(login_groups))
  if [ "$got" = allowed ]; then ok "companion: the current login may change Kyverno's ConfigMap"; else bad "companion: the current login must be allowed, got $got"; fi
  got=$(classify oc patch cm kyverno -n kyverno --type=merge -p '{"data":{"verify-probe":"x"}}' --dry-run=server --as=probe-admin --as-group=app-ocp-rbac-alpha-cluster-admin --as-group=system:authenticated)
  if [ "$got" = allowed ]; then ok "companion: the -cluster-admin tier (platform admins) may change Kyverno's ConfigMap"; else bad "companion: the -cluster-admin tier must be allowed, got $got"; fi
else
  say "  info  companion vap-protect-kyverno-configuration.yaml is not applied; the edit tier can change Kyverno's configuration"
fi

say "result: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
