# Manual documentation (versioned source)

Put hand-written manual docs under version folders.

Directory structure:

```text
manual/
  <version>/
    index.md
    index.ja.md
    index.ko.md
    images/
```

Publish command:

```bash
./scripts/publish_docs.sh <version>
```

How it is copied:

- source: `manual/<version>/`
- output: `docs/<version>/manual/`

`docs/latest/` behavior:

- `docs/latest/` is refreshed from the highest version under `docs/`.
- `docs/latest/manual/` therefore reflects the manual from that highest version.
- `docs/latest/VERSION.txt` stores the latest version.

Notes:

- Recommended entry files:
  - `index.md` (English)
  - `index.ja.md` (Japanese)
  - `index.ko.md` (Korean)
