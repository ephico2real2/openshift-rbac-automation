<!-- Generated from docs/onboarding/ONBOARDING_CHECKLIST.md.in by docs/onboarding/render.sh: edit the source, not this file. -->

# Developer onboarding checklist

Tick every box, in order. Each item links to the step in the [guide](ONBOARDING.md) that explains it. The examples
use the mnemonic `pay`; use your own.

## Before you ask for namespaces

- [ ] I know my application's mnemonic: three lowercase letters, such as `pay`. ([§2](ONBOARDING.md#2-before-you-start))
- [ ] I know who the mnemonic owner is. ([§2](ONBOARDING.md#2-before-you-start))
- [ ] `app-ocp-rbac-<mnemonic>-ns-audit` exists in the `rnd`, `qa`, `uat` and `prod` directories, spelled exactly.
      ([§3](ONBOARDING.md#3-step-1-the-groups-in-each-environments-directory), [§4](ONBOARDING.md#4-step-2-confirm-the-groups-exist-before-you-ask-for-namespaces))
- [ ] `app-ocp-rbac-<mnemonic>-ns-developer` exists in the `rnd`, `qa` and `uat` directories, and not in `prod`.
      ([§3](ONBOARDING.md#3-step-1-the-groups-in-each-environments-directory))
- [ ] In each environment, each group I need has its members, approved by the mnemonic owner. ([§3](ONBOARDING.md#3-step-1-the-groups-in-each-environments-directory))
- [ ] The dashboard's **Your groups** (on Home) lists my groups. ([§4](ONBOARDING.md#4-step-2-confirm-the-groups-exist-before-you-ask-for-namespaces))
- [ ] Everyone on the team can log in to OpenShift. ([§8](ONBOARDING.md#8-when-something-is-wrong))

## Asking for namespaces

- [ ] My namespace request gives my mnemonic, the same three letters as in the group names.
      ([§2](ONBOARDING.md#2-before-you-start), [§5](ONBOARDING.md#5-step-3-ask-for-your-namespaces))
- [ ] It gives each namespace's environment as exactly `rnd`, `qa`, `uat` or `prod`; the namespace template turns
      these into the `company.net/mnemonic` and `company.net/app-environment` labels.
      ([§5](ONBOARDING.md#5-step-3-ask-for-your-namespaces))

## After the namespaces exist

- [ ] Each namespace's page in the dashboard shows the `mnemonic` and `app-environment` I asked for.
      ([§6](ONBOARDING.md#6-step-4-check-your-access))
- [ ] The dashboard's Home lists my namespaces, each "via" one of my groups. ([§6](ONBOARDING.md#6-step-4-check-your-access))
- [ ] `oc auth can-i create deployments` answers yes in my `rnd`, `qa` and `uat` namespaces, if I am in the developer
      group in that environment's directory. ([§6](ONBOARDING.md#6-step-4-check-your-access))
- [ ] `oc auth can-i create deployments` answers no in `prod`, and `oc auth can-i get pods` answers yes there if I am in
      the audit group in the `prod` directory. ([§6](ONBOARDING.md#6-step-4-check-your-access))

## Keeping it right

- [ ] I ask the mnemonic owner when someone joins or leaves, and I never ask for access by name.
      ([§7](ONBOARDING.md#7-living-with-it))
- [ ] I know that someone removed in the directory keeps their access until the next group sync, and that the
      dashboard shows the change after that. ([§7](ONBOARDING.md#7-living-with-it))
- [ ] I know the mnemonic owner reviews our groups' members in every environment each quarter. ([§7](ONBOARDING.md#7-living-with-it))
