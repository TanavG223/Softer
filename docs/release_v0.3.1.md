# PaceBack v0.3.1

Artifact: `PaceBack-0.3.1-macOS-universal.zip`

SHA-256:

```text
31e867af874317527383d1e214bb01625a8f31d4e1ffc9014aeda8c6226913b4
```

The ZIP contains a universal arm64/x86_64 native app. Both executable slices
declare macOS 14.0 as their minimum deployment target. The extracted archive
passed strict deep code-signature verification, and the packaged About screen
was observed reporting version 0.3.1.

This prototype is Apple Development-signed but not Developer ID notarized.
After downloading and verifying the checksum, unzip the archive, Control-click
**PaceBack.app**, choose **Open**, and confirm **Open**. If macOS still blocks
it, use **System Settings → Privacy & Security → Open Anyway**. Do not
disable Gatekeeper globally.

This patch corrects release-version display, preserves native semantics for the
public support links, and repairs inherited game/support color combinations in
both light and dark themes. It does not change the activity, recommendation,
support, persistence, or game state machines covered by the 58-check
verification harness.
