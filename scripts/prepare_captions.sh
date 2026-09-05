#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
source_srt="$repo_dir/output/video/transcript/softer-whisper.srt"
target_srt="$repo_dir/docs/video/softer-captions.srt"

if [[ ! -f "$source_srt" ]]; then
  print -u2 "Missing Whisper transcript: $source_srt"
  exit 1
fi

sed \
  -e 's/^ //' \
  -e 's/Softor/Softer/g' \
  -e 's/softer/Softer/g' \
  -e 's/plain language/plain-language/g' \
  -e 's/Gentle breathing/Gentle Breathing/g' \
  -e 's/Reduce motion/Reduce Motion/g' \
  -e 's/harbor tiles/Harbor Tiles/g' \
  -e 's/The need help\./The Need Help Now route/' \
  -e 's/Now route remains available even when/remains available even when/' \
  -e 's/SwiftUI CryptoKit/SwiftUI, CryptoKit,/' \
  -e 's/Mac OS/macOS/g' \
  -e 's/chat bot/chatbot/g' \
  -e 's/cloud back end/cloud backend/g' \
  -e 's/^58 behavioral/Fifty-eight behavioral/' \
  -e 's/mental health outcome/mental-health outcome/g' \
  "$source_srt" > "$target_srt"

print "$target_srt"
