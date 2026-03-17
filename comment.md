Although not enforced by the operator the general expectation is that the NamespaceConfig CR will be used to create objects inside the selected namespace.

Examples of NamespaceConfig usages can be found [here](https://github.com/redhat-cop/namespace-configuration-operator/blob/master/examples/namespace-config/readme.md)

## GroupConfig

The `GroupConfig` CR allows specifying one or more objects that will be created in the selected Group.
Groups can be selected by labels or annotations via a label selector, similarly to the `NamespaceConfig`.

Often groups are created in OpenShift by a job that synchronizes an Identity Provider with OCP. So the idea is that when new groups are added or deleted the configuration in OpenShift will adapt automatically.

Although not enforced by the operator, GroupConfig are expected to create cluster-scoped resources like Namespaces, ClusterResourceQuotas and potentially some namespaced resources like RoleBindings.

## UserConfig

In OpenShift an external user is defined by two entities: Users and Identities. There is a relationship of on to many between Users and Identities. Given one user, there can be one Identity per authentication mechanism.

The `UserConfig` CR allows specifying one or more objects that will be created in the selected User.
Users can be selected by label or annotation like `NamespaceConfig` and `UserConfig`.
USers can also be selected by provider name (the name of the authentication mechanism) and identity extra field.

Here is an example:
