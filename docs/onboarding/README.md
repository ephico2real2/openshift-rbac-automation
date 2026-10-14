# Developer onboarding: the sources

The developer onboarding guide and checklist are written here and rendered into `docs/`:

| Source | Renders to |
|---|---|
| `ONBOARDING.md.in` | [`docs/ONBOARDING.md`](../ONBOARDING.md) |
| `ONBOARDING_CHECKLIST.md.in` | [`docs/ONBOARDING_CHECKLIST.md`](../ONBOARDING_CHECKLIST.md) |
| both rendered files | [`docs/ONBOARDING.docx`](../ONBOARDING.docx): the guide, a page break, the checklist, for people who use Word |

The namespace label keys are written `@LABEL_DOMAIN@/mnemonic` and `@LABEL_DOMAIN@/app-environment` in the sources.
The domain itself is set once, in `onboarding.env`, beside `DOC_DATE`, the date stamped on the Word file.

`render.sh` builds the Word file with diagram-kit's `doc-docx` (kit v0.2.5 and pandoc 3.12.1, the versions CI pins,
because the file's bytes depend on them; see the kit's `/document` skill).

- **To change the wording:** edit the `.md.in` source, run `docs/onboarding/render.sh`, and commit the source with
  the rendered files (the Markdown and the Word file).
- **To change the label domain** (for example from `company.net`): edit the one line in `onboarding.env`, run
  `docs/onboarding/render.sh`, and commit `onboarding.env` and the three rendered files.

Never edit `docs/ONBOARDING.md`, `docs/ONBOARDING_CHECKLIST.md` or `docs/ONBOARDING.docx` by hand: CI renders them
again and fails the pull request if they differ.
