# Softer v0.4.0

Artifact: `Softer-0.4.0-macOS-universal.zip`

SHA-256:

```text
e14ee37a9d524a43ea0a4cf551f9e664658a03b89e0118dbc5ff4e435e83502f
```

This universal release contains native Apple silicon and Intel executables and
requires macOS 14 or newer. It is Apple Development-signed with hardened runtime
but is not Developer ID notarized.

After downloading, verify the archive:

```sh
shasum -a 256 Softer-0.4.0-macOS-universal.zip
```

After unzipping, Control-click **Softer.app**, choose **Open**, and confirm
**Open**. If macOS still blocks it, use **System Settings -> Privacy & Security
-> Open Anyway**.

The 0.4.0 release renames the product from PaceBack to Softer while retaining
legacy storage identifiers so an existing encrypted local profile is not
stranded. The current acceptance record is in
[`release_acceptance_2026-09-04.md`](release_acceptance_2026-09-04.md).
