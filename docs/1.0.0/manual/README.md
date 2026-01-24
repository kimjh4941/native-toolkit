# Manual documentation (source)

Put hand-written documentation here.

This folder is treated as _source_ content and will be copied into versioned output by:

```bash
./scripts/publish_docs.sh <version>
```

Published location:

- `docs/<version>/manual/`
- `docs/latest/manual/`

Notes:

- Recommended entry files:

  - `index.md` (English)
  - `index.ja.md` (Japanese)
  - `index.ko.md` (Korean)

- This repository's generated docs are HTML (Dokka/DocC/Doxygen). If you want manual docs to be browsable on static hosting, consider writing HTML here or add a separate Markdown->HTML step later.
