#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
frames_dir="$project_root/output/video/frames"
work_dir="$project_root/output/video/render-work"
silent_video="$project_root/output/video/softer-demo-silent.mp4"
final_video="$project_root/output/video/Softer-Hack-for-Humanity-demo.mp4"
clean_video="$project_root/output/video/softer-demo-clean.mp4"
narration="$project_root/output/video/softer-elevenlabs-narration.mp3"
captions="$project_root/docs/video/softer-captions.srt"

cd "$project_root"

mkdir -p "$work_dir"

scene_files=(
  "00-title.png"
  "01-calm.png"
  "01b-private-start.png"
  "02-choices.png"
  "03-breathing.png"
  "04a-tiles-hint.png"
  "04b-tiles-placed.png"
  "04c-tiles-undo.png"
  "04d-play.png"
  "04e-finite-play.png"
  "05-checkout.png"
  "06-support.png"
  "07-privacy.png"
  "08-about.png"
  "07b-local-design.png"
  "09-closing.png"
)

scene_durations=(6 20 15 20 20 8 9 7 8 8 25 23 12 8 10 7)

for index in {1..${#scene_files[@]}}; do
  source_file="$frames_dir/${scene_files[$index]}"
  duration="${scene_durations[$index]}"
  scene_number=$(printf "%02d" "$index")
  output_file="$work_dir/scene-$scene_number.mp4"
  fade_out=$(awk -v d="$duration" 'BEGIN { printf "%.2f", d - 0.25 }')

  if [[ ! -f "$source_file" ]]; then
    print -u2 "Missing scene source: $source_file"
    exit 1
  fi

  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -framerate 30 -t "$duration" -i "$source_file" \
    -vf "scale=-2:1000:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x081315,fade=t=in:st=0:d=0.25,fade=t=out:st=$fade_out:d=0.25,format=yuv420p" \
    -r 30 -c:v libx264 -preset medium -crf 18 -an "$output_file"
done

concat_file="$work_dir/scenes.txt"
: > "$concat_file"
for index in {1..${#scene_files[@]}}; do
  scene_number=$(printf "%02d" "$index")
  print -r -- "file '$work_dir/scene-$scene_number.mp4'" >> "$concat_file"
done

ffmpeg -y -hide_banner -loglevel error \
  -f concat -safe 0 -i "$concat_file" \
  -c copy "$silent_video"

ffmpeg -y -hide_banner -loglevel error \
  -i "$silent_video" -i "$narration" \
  -filter_complex "[1:a]adelay=1000:all=1,loudnorm=I=-16:TP=-1.5:LRA=11,apad=pad_dur=2[a]" \
  -map 0:v:0 -map "[a]" \
  -t 206 -c:v copy -c:a aac -b:a 192k -ac 2 -ar 48000 \
  -movflags +faststart \
  -metadata title="Softer — Make the next minute smaller" \
  -metadata comment="Narration generated with an ElevenLabs stock synthetic voice." \
  "$clean_video"

if ffmpeg -hide_banner -filters 2>/dev/null | grep -q ' subtitles '; then
  ffmpeg -y -hide_banner -loglevel error \
    -i "$clean_video" \
    -vf "subtitles=filename=docs/video/softer-captions.srt:force_style='FontName=Arial,FontSize=21,PrimaryColour=&H00FFFFFF,BackColour=&H9A081315,BorderStyle=3,Outline=1,Shadow=0,MarginV=34,Alignment=2'" \
    -c:v libx264 -preset medium -crf 18 \
    -c:a copy -movflags +faststart \
    -metadata title="Softer — Make the next minute smaller" \
    -metadata comment="Narration generated with an ElevenLabs stock synthetic voice; English captions are burned in." \
    "$final_video"
else
  cp "$clean_video" "$final_video"
  print -u2 "ffmpeg lacks libass; kept captions as docs/video/softer-captions.srt"
fi

print -r -- "$final_video"
