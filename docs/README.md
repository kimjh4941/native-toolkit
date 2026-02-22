# Published documentation (versioned output)

This repository publishes documentation by version.

- Latest: `latest/`
- Versions: `<version>/` (e.g., `1.0.0/`, `1.1.0/`)

The file `latest/VERSION.txt` contains the version currently published as `latest/`.

`latest/` is always refreshed from the highest version directory under `docs/`.

## How to publish

From repository root:

```bash
./scripts/publish_docs.sh 1.1.0
```

If you already generated docs and only want to copy/update:

```bash
./scripts/publish_docs.sh 1.1.0 --skip-build
```

## Build behavior

By default, `publish_docs.sh` generates docs first when possible:

- Android: Dokka (`android_library`, `unity_android_plugin`)
- iOS: DocC (`ios/generate_docc.sh`)
- macOS: DocC (`mac/generate_docc.sh`)
- Windows: Doxygen (if `doxygen` is installed)

With `--skip-build`, the script only copies existing outputs and refreshes `latest/`.

## Output layout

Each version directory contains per-platform docs (when available):

- `android/`
- `ios/`
- `mac/`
- `windows/`

## Hand-written docs

Hand-written docs should live under:

- `manual/<version>/`

They are published into:

- `docs/<version>/manual/`

Because `docs/latest/` is copied from the highest version under `docs/`,
`docs/latest/manual/` reflects the manual of that highest version.
