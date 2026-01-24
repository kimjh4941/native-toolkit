# Versioned documentation

This repository publishes documentation by version.

- Latest: `latest/`
- Versions: `<version>/` (e.g., `1.0.0/`, `1.1.0/`)

The file `latest/VERSION.txt` contains the version currently published as `latest/`.

## How to publish

From repository root:

```bash
./scripts/publish_docs.sh 1.1.0
```

If you already generated docs and only want to copy/update:

```bash
./scripts/publish_docs.sh 1.1.0 --skip-build
```

## Output layout

Each version directory contains per-platform docs (when available):

- `android/`
- `ios/`
- `mac/`
- `windows/`

## Hand-written docs

Hand-written docs should live under:

- `docs_src/manual/`

They are published into:

- `docs/<version>/manual/`
- `docs/latest/manual/`
