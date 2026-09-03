# Verifying a policy on a live cluster: the Spark job submitter role

A short, repeatable check that a member of an `oud-group` family can do exactly what the chart's
`spark-job-submitter-role` grants in their namespace, and nothing else. Every command below was run
against the reference CRC cluster on 2026-09-03 and the output shown is what came back.

The example is the `bda-rbac-spark-theta-apps` group and the `oud-poc-spark` namespace. Substitute
your own group and namespace; the shape of the check is the same for any policy this chart renders.

You need `oc` logged in as a cluster administrator (`kubeadmin` on CRC). Nothing here changes the
policy; the only writes are the throwaway test objects in step 6, which step 7 deletes.

## 1. What is assigned: the Role

Start from the object the policy produced. The operator writes the Role into every namespace whose
label matches the policy, and the Role is the single source of truth for what a member may do.

```bash
oc get role.rbac.authorization.k8s.io spark-job-submitter-role -n oud-poc-spark \
  -o jsonpath='{range .rules[*]}{.apiGroups}{" "}{.resources}{" "}{.verbs}{"\n"}{end}'
```

```
[""] ["pods","services","configmaps","persistentvolumeclaims"] ["create","get","list","watch","delete","deletecollection","patch","update"]
[""] ["secrets"] ["create","get","watch","delete","update","patch"]
[""] ["pods/log"] ["get","list"]
```

Three rules. Full lifecycle on pods, services, configmaps and persistentvolumeclaims; the same on
secrets minus `list`, so a member can use a secret they know the name of but cannot enumerate the
namespace's secrets; and read-only pod logs. Note what is absent: nothing in `apps` (no
deployments), nothing cluster-scoped, and only this namespace.

The resource name is spelled out in full (`role.rbac.authorization.k8s.io`) on purpose. A short name
can bind to a different API group on a cluster with extra CRDs installed, and a misrouted `get`
returns "not found" rather than an error, which reads as "the policy did not render".

## 2. Who it is bound to: the RoleBinding

```bash
oc get rolebinding.rbac.authorization.k8s.io -n oud-poc-spark -o json \
  | python3 -c 'import json,sys
for rb in json.load(sys.stdin)["items"]:
    if rb["roleRef"]["name"] == "spark-job-submitter-role":
        print(rb["metadata"]["name"], "->", rb["roleRef"]["kind"], rb["roleRef"]["name"],
              "| subjects:", [(s["kind"], s["name"]) for s in rb.get("subjects", [])])'
```

```
bda-rbac-spark-theta-apps-rb -> Role spark-job-submitter-role | subjects: [('Group', 'bda-rbac-spark-theta-apps')]
```

One binding, to a Group, never to a person. The group name is the namespace's label value, which
is the whole design of the `oud-group` policy: whoever holds the label decides who holds the access.

```bash
oc get namespace oud-poc-spark -o jsonpath='{.metadata.labels.company\.net/oud-group}{"\n"}'
```

```
bda-rbac-spark-theta-apps
```

## 3. Who is in the group, and pick a member

The Group object is written by the group-sync operator from the directory. Its `users` list is what
the cluster consults when it decides whether a request comes from a member.

```bash
oc get group.user.openshift.io bda-rbac-spark-theta-apps -o jsonpath='{.users}{"\n"}'
```

```
["john.doe"]
```

Pick one member for the test. With several, any will do; the check is about the group, and every
member gets the same binding. Here the group has one, so the test identity is `john.doe`.

```bash
MEMBER=$(oc get group.user.openshift.io bda-rbac-spark-theta-apps -o jsonpath='{.users[0]}')
echo "$MEMBER"
```

```
john.doe
```

## 4. Ask the cluster, before touching anything

`oc auth can-i` sends a SubjectAccessReview: the API server answers from its own RBAC, so this is the
cluster's opinion, not a reading of the YAML. It can be asked on behalf of another identity.

**The trap, first, because it produces a convincing wrong answer.** Impersonating the user name alone
does not carry OpenShift Group membership. `--as=` builds an identity from the flags you pass and
nothing else, so a bare `--as=john.doe` is john.doe in no groups at all:

```bash
oc auth can-i create pods -n oud-poc-spark --as="$MEMBER"
```

```
no
```

That "no" is the test method, not the policy. Attach the group, the way the authenticator does on a
real login, and ask again:

```bash
AS=(--as="$MEMBER" --as-group=bda-rbac-spark-theta-apps --as-group=system:authenticated)

for r in pods services configmaps persistentvolumeclaims secrets; do
  printf '%-24s create: %s\n' "$r" "$(oc auth can-i create "$r" -n oud-poc-spark "${AS[@]}")"
done
printf '%-24s get:    %s\n' pods/log "$(oc auth can-i get pods --subresource=log -n oud-poc-spark "${AS[@]}")"
```

```
pods                     create: yes
services                 create: yes
configmaps               create: yes
persistentvolumeclaims   create: yes
secrets                  create: yes
pods/log                 get:    yes
```

`AS` is an array, not a string. In zsh an unquoted `$AS` is passed as one argument, and `oc` then
impersonates a user literally named `john.doe --as-group=…`, whose every request is forbidden. The
error message names that user, which is how you tell this mistake from a real denial.

## 5. Ask the negatives too

A policy that grants too much passes step 4 just as well. Check what the role does not say:

```bash
oc auth can-i create deployments.apps -n oud-poc-spark "${AS[@]}"   # not in the role
oc auth can-i create pods -n default "${AS[@]}"                     # another namespace
oc auth can-i create pods -n oud-poc-trino "${AS[@]}"               # another family's namespace
```

```
no
no
no
```

## 6. Create every resource the role names, as the member

`can-i` proves authorization. Creating the objects proves the whole path, admission included, and
exercises `patch` and `pods/log` as well. Every call is made as the member with their group.

```bash
NS=oud-poc-spark
T=rbac-test-$(date +%s)          # one name for every object, so cleanup is one command

oc "${AS[@]}" -n "$NS" create configmap "$T" --from-literal=k=v
oc "${AS[@]}" -n "$NS" create secret generic "$T" --from-literal=k=v
oc "${AS[@]}" -n "$NS" create service clusterip "$T" --tcp=80:80

cat <<EOF | oc "${AS[@]}" -n "$NS" create -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $T}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Mi}}}
EOF

cat <<EOF | oc "${AS[@]}" -n "$NS" create -f -
apiVersion: v1
kind: Pod
metadata: {name: $T}
spec:
  restartPolicy: Never
  containers:
    - name: t
      image: registry.access.redhat.com/ubi9/ubi-minimal
      command: [sh, -c, "echo spark-test-ok"]
EOF
```

```
configmap/rbac-test-1788434877 created
secret/rbac-test-1788434877 created
service/rbac-test-1788434877 created
persistentvolumeclaim/rbac-test-1788434877 created
pod/rbac-test-1788434877 created
```

Then the verbs beyond `create`:

```bash
oc "${AS[@]}" -n "$NS" patch secret "$T" -p '{"stringData":{"k":"v2"}}'

oc -n "$NS" wait pod/"$T" --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s   # as admin: just waiting
oc "${AS[@]}" -n "$NS" logs "$T"
```

```
secret/rbac-test-1788434877 patched
spark-test-ok
```

And the same negatives as live calls, which must fail:

```bash
oc "${AS[@]}" -n "$NS" create deployment "$T" --image=x
oc "${AS[@]}" -n default create configmap "$T" --from-literal=k=v
oc "${AS[@]}" -n oud-poc-trino create configmap "$T" --from-literal=k=v
```

```
error: failed to create deployment: deployments.apps is forbidden: User "john.doe" cannot create resource "deployments" in API group "apps" in the namespace "oud-poc-spark"
error: failed to create configmap: configmaps is forbidden: User "john.doe" cannot create resource "configmaps" in API group "" in the namespace "default"
error: failed to create configmap: configmaps is forbidden: User "john.doe" cannot create resource "configmaps" in API group "" in the namespace "oud-poc-trino"
```

The denial names `User "john.doe"` and nothing else. That is the shape of a real refusal.

## 7. Clean up, as the member

`delete` is in the role, so the member removes their own test objects. Doing it as the member is one
more verb verified.

```bash
oc "${AS[@]}" -n "$NS" delete pod/"$T" service/"$T" configmap/"$T" secret/"$T" pvc/"$T"
oc get pod,service,configmap,secret,pvc -A | grep -c "$T"    # expect 0
```

```
pod "rbac-test-1788434877" deleted
service "rbac-test-1788434877" deleted
configmap "rbac-test-1788434877" deleted
secret "rbac-test-1788434877" deleted
persistentvolumeclaim "rbac-test-1788434877" deleted
0
```

## What this proves, and what it does not

It proves the RBAC: with the group attached, the API server authorizes the member for exactly the
verbs and kinds the Role names, in this namespace only, and admission accepts the resulting objects.

It does not prove that a real login attaches the group. Impersonation supplies the group list
itself; on a real session the OAuth authenticator supplies it from the Group object read in step 3.
That is OpenShift's mechanism rather than this chart's, and the Group object listing the member is
the fact it consults. To close that last gap, log in as the member and rerun steps 4 to 7 without
the `--as` flags:

```bash
oc login https://api.crc.testing:6443 -u "$MEMBER" --kubeconfig=/tmp/member.kubeconfig
oc --kubeconfig=/tmp/member.kubeconfig auth can-i create pods -n oud-poc-spark
```

On the reference lab this was not possible: the LDAP seed stores `{SSHA}password123` as a literal
rather than a hash, so the directory refuses every password for the seeded personas (measured: 401).
On a cluster whose members can sign in, the login form is the stronger test.
