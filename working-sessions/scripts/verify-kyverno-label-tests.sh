#!/bin/bash
# Compare Kyverno's actual verdicts against the expectations declared in
# kyverno-label-test-namespaces.yaml. Prints a pass/fail table; exits non-zero if any
# verdict differs, so it can gate a change to the policies.
#
# Usage: ./verify-kyverno-label-tests.sh
set -uo pipefail

# namespace|rule-suffix|expected
EXPECT="
klt-pass-both|require-rbac-labels|pass
klt-pass-both|validate-environment-values|pass
klt-pass-both|consistency-app-ocp-rbac|pass
klt-pass-mnemonic-3char|require-rbac-labels|pass
klt-pass-mnemonic-3char|consistency-app-ocp-rbac|pass
klt-fail-no-labels|require-rbac-labels|fail
klt-fail-only-mnemonic|require-rbac-labels|fail
klt-fail-only-mnemonic|consistency-app-ocp-rbac|pass
klt-fail-only-env|require-rbac-labels|fail
klt-fail-only-env|validate-environment-values|pass
klt-fail-bad-env|validate-environment-values|fail
klt-fail-mnemonic-toolong|consistency-app-ocp-rbac|fail
klt-fail-mnemonic-toolong|require-rbac-labels|pass
ocp-klt-excluded-no-labels|require-rbac-labels|absent
"

oc get clusterpolicyreport -o json 2>/dev/null > /tmp/klt-report.json

fails=0
printf "  %-28s %-34s %-8s %-8s %s\n" NAMESPACE RULE EXPECT ACTUAL ""
while IFS='|' read -r ns rule exp; do
  [ -z "$ns" ] && continue
  actual=$(python3 - "$ns" "$rule" <<'PY'
import sys, json
ns, rule = sys.argv[1], sys.argv[2]
d = json.load(open('/tmp/klt-report.json'))
for rep in d.get('items', []):
    if (rep.get('scope') or {}).get('name') != ns:
        continue
    for r in rep.get('results', []):
        if rule in r.get('rule', ''):
            print(r.get('result')); raise SystemExit
print('absent')
PY
)
  if [ "$actual" = "$exp" ]; then mark="ok"; else mark="MISMATCH"; fails=$((fails+1)); fi
  printf "  %-28s %-34s %-8s %-8s %s\n" "$ns" "$rule" "$exp" "$actual" "$mark"
done <<< "$EXPECT"

rm -f /tmp/klt-report.json
echo
if [ "$fails" -eq 0 ]; then
  echo "  ALL EXPECTATIONS MET"
else
  echo "  $fails MISMATCH(ES) — policy behaviour has changed"
fi
exit $fails
