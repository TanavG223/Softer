# Softer demo video validation

Validated on 2026-09-04 against the packaged Softer 0.4.0 macOS application.

## Deliverables

- Local video: `output/video/Softer-Hack-for-Humanity-demo.mp4`
- ElevenLabs narration: `output/video/softer-elevenlabs-narration.mp3`
- Upload captions: `docs/video/softer-captions.srt`
- Narration source: `docs/video/softer-narration.txt`
- YouTube description: `docs/video/youtube-description.md`
- Published YouTube video: <https://youtu.be/oAyuhxrKdoY> (unlisted)

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
- Synthetic narration is disclosed in the published YouTube description and in the MP4 metadata.
- YouTube reported no copyright issues.
- A custom 1280 by 720 Softer thumbnail was uploaded.
- English (United States) captions were uploaded from the validated SRT and published.
- The public watch page loaded the correct title, unlisted visibility, 3:26 duration, and an actively playing video.
- Caption playback was spot-checked at the opening, 2:50, 3:18, and 3:24. The final visible line was “by keeping every choice clear, private, and optional.”
- YouTube's oEmbed endpoint returned the correct title, author, public thumbnail URL, and embeddable player markup for the watch URL.

## Remaining owner-controlled gates

Before the YouTube URL is added to Devpost, the project owner should still:

1. Listen to the complete YouTube video once with sound.
2. Open the final watch URL in a signed-out browser window and confirm 1080p playback and captions.
3. Only then add the URL to Devpost.

Codex verified the watch page in the in-app browser. A separate signed-out browser context was not available, so the signed-out acceptance gate remains deliberately unclaimed.
