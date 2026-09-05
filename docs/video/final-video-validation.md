# Softer demo video validation

Validated on 2026-09-04 against the packaged Softer 0.4.0 macOS application.

## Deliverables

- Local video: `output/video/Softer-Hack-for-Humanity-demo.mp4`
- ElevenLabs narration: `output/video/softer-elevenlabs-narration.mp3`
- Upload captions: `docs/video/softer-captions.srt`
- Narration source: `docs/video/softer-narration.txt`
- YouTube description: `docs/video/youtube-description.md`

## Media contract

- Container: MP4
- Video: H.264, 1920 by 1080, constant 30 fps
- Audio: AAC, 48 kHz, stereo
- Duration: 206 seconds (3:26), below the hackathon's four-minute limit
- File size: 8,588,839 bytes
- SHA-256: `751919174a029621e4e3cbcc9a6302f89d3f23e5459fa376d65c9a83faceb3af`
- Integrated loudness: -17.2 LUFS
- True peak: -4.2 dBTP
- Black-frame scan: no interval at least 0.6 seconds was detected at a 0.01 pixel threshold

## Content verification

- Every product frame was captured from the running packaged application after the corresponding control was exercised.
- Calm, the explicit need picker, Gentle Breathing, Harbor Tiles with Hint and Undo, checkout, Support, Privacy, and About are visible.
- No emergency, message, contact, or external-support action was activated.
- No profile name, notification, secret, or unrelated application is visible.
- The original ElevenLabs MP3 was transcribed locally with whisper.cpp `base.en`. The complete spoken content was present. The only corrections needed in the upload SRT were capitalization, product-name spelling, and punctuation.
- Claims are limited to observable behavior and software verification. The narration explicitly says that Softer does not diagnose, treat, promise calm, or demonstrate a mental-health outcome.
- Synthetic narration is disclosed in the prepared YouTube description and in the MP4 metadata.

## Remaining owner-controlled gates

The video is not considered submission-ready until its uploader:

1. Watches the local MP4 with sound.
2. Uploads the MP4 and `softer-captions.srt` to YouTube.
3. Confirms the video is not marked as made for children and makes it public or unlisted.
4. Opens the final watch URL while signed out, checks 1080p playback and captions, and only then adds that URL to Devpost.

The Codex in-app browser can fill and verify web forms, but its sandbox cannot attach a local file to YouTube's native file chooser. That one file-selection step must be completed by the account owner.
