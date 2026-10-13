# Developer onboarding: the sources

The developer onboarding guide and checklist are written here and rendered into `docs/`:

| Source | Renders to |
|---|---|
| `ONBOARDING.md.in` | [`docs/ONBOARDING.md`](../ONBOARDING.md) |
| `ONBOARDING_CHECKLIST.md.in` | [`docs/ONBOARDING_CHECKLIST.md`](../ONBOARDING_CHECKLIST.md) |

The namespace label keys are written `@LABEL_DOMAIN@/mnemonic` and `@LABEL_DOMAIN@/app-environment` in the sources.
The domain itself is set once, in `onboarding.env`.

- **To change the wording:** edit the `.md.in` source, run `docs/onboarding/render.sh`, and commit the source and the
  rendered file together.
- **To change the label domain** (for example from `company.net`): edit the one line in `onboarding.env`, run
  `docs/onboarding/render.sh`, and commit `onboarding.env` and both rendered files.

Never edit `docs/ONBOARDING.md` or `docs/ONBOARDING_CHECKLIST.md` by hand: CI renders them again and fails the pull
request if they differ.
