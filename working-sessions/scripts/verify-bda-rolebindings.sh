#!/bin/bash
# =============================================================================
# Resolve every BDA RoleBinding to its ACTUAL group membership.
# =============================================================================
# WHY THIS EXISTS
# `oc get rolebinding` cannot tell a working binding from a dead one. Kubernetes
# never validates that a RoleBinding's subject Group exists, so a binding naming a
# group that was never created is stored, reported healthy, and grants nobody — with
# no error, no event, and no failed reconcile.
#
# A dead binding is byte-for-byte indistinguishable from a live one in `oc get`
# output: same name pattern, same roleRef, same age, same managed-by label, same
# source annotation. The ONLY difference is whether the subject resolves.
#
# This script does that resolution, so the difference becomes visible:
#
#   subject : Group/bda-rbac-spark-alpha-users   -> members=bob.wilson,jane.smith
#   subject : Group/bda-rbac-spark-gamma-users   -> GROUP MISSING
#
# Three states are distinguished, and they mean different things:
#   members=<names>           working
#   group exists but EMPTY    group synced, nobody in it in LDAP — grants nobody,
#                             but ARMS the moment a member is added upstream
#   GROUP MISSING             no such Group object — usually a typo'd namespace label
#                             or a group that was never created in LDAP
#
# NOTE: `oc auth can-i --as-group=<name>` is NOT a substitute. Impersonation lets you
# assert membership of a group that does not exist and will answer "yes", proving only
# that the binding is wired correctly — not that any real user can use it.
#
# Usage:   ./verify-bda-rolebindings.sh
# Scope:   every namespace carrying company.net/bda-team
# Read-only. Safe to run at any time.
# =============================================================================
set -uo pipefail

SUFFIX="${SUFFIX:-bda-workload-submitter-rb}"
LABEL="${LABEL:-company.net/bda-team}"

ns_list=$(oc get ns -l "$LABEL" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "$ns_list" ]; then
  echo "No namespaces carry the label $LABEL"
  exit 0
fi

echo "$ns_list" | while read -r ns; do
  [ -z "$ns" ] && continue
  echo "##### $ns #####"
  oc get rolebinding -n "$ns" -o json 2>/dev/null | SUFFIX="$SUFFIX" python3 -c "
import sys, json, os, subprocess

suffix = os.environ['SUFFIX']

# One lookup of all Groups, then resolve locally. Distinguishes 'missing' (absent
# from the dict) from 'empty' (present with no users) — they are different failures.
groups = {g['metadata']['name']: (g.get('users') or [])
          for g in json.loads(subprocess.run(
              ['oc', 'get', 'groups', '-o', 'json'],
              capture_output=True, text=True).stdout)['items']}

for r in json.load(sys.stdin)['items']:
    if not r['metadata']['name'].endswith(suffix):
        continue
    m = r['metadata']
    print(f\"  RoleBinding : {m['name']}\")
    print(f\"  roleRef     : {r['roleRef']['kind']}/{r['roleRef']['name']}\")
    for s in r.get('subjects') or []:
        u = groups.get(s['name'])
        if u is None:
            state = 'GROUP MISSING'
        elif not u:
            state = 'group exists but EMPTY'
        else:
            state = 'members=' + ','.join(u)
        print(f\"  subject     : {s['kind']}/{s['name']}   -> {state}\")
    print(f\"  from label  : {(m.get('labels') or {}).get('rbac.ocp.io/bda-team')}\")
    print(f\"  source cfg  : {(m.get('annotations') or {}).get('rbac.ocp.io/source-namespaceconfig')}\")
"
  echo
done
