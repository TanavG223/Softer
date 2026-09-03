# PaceBack v0.3.0 release candidate

Artifact: `PaceBack-0.3.0-macOS-universal.zip`

SHA-256:

```text
901ba49662323e4811a1ccca450f63aa8e9b1d7f01a446dc9fe9d8c44061a8ae
```

The ZIP contains a universal arm64/x86_64 native app. Both executable slices
declare macOS 14.0 as their minimum deployment target. The app is Apple
Development-signed for prototype testing; it is not Developer ID notarized, so
Gatekeeper rejects a normal first launch on an unrelated Mac.

After downloading and verifying the checksum, unzip the archive, Control-click
**PaceBack.app**, choose **Open**, and confirm **Open**. If macOS still blocks
it, use **System Settings → Privacy & Security → Open Anyway**. Do not disable
Gatekeeper globally.
