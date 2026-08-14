#!/usr/bin/env bash

set -eu
shopt -s nullglob

BASE="/Users/angusblakeuni/Documents/transcriptions"
DOWNLOADS="$HOME/Downloads"
VAULT="$HOME/Obsidian/MyVault/1_Projects"
MODEL="mlx-community/parakeet-tdt-0.6b-v3"
FAST_MODEL="mlx-community/parakeet-tdt_ctc-110m"
CHUNK=120

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"

MATCH="/section/"
CREATED_TAB=0
CREATED_WINDOW=1
CREATED_INDEX=0
OUR_TAB_URL=""

run_js() {
  osascript <<APPLESCRIPT
set js to read POSIX file "$1"
tell application "Safari"
  set found to missing value
  repeat with w from 1 to (count of windows)
    repeat with t from 1 to (count of tabs of window w)
      if (URL of tab t of window w as string) contains "${2:-$MATCH}" then
        set found to tab t of window w
      end if
    end repeat
  end repeat
  if found is missing value then return "NO_TAB"
  return (do JavaScript js in found)
end tell
APPLESCRIPT
}

eval_js() {
  printf '%s' "$1" > "$TMP/eval.js"
  run_js "$TMP/eval.js" "${2:-$MATCH}"
}

open_tab() {
  osascript -e "tell application \"Safari\" to make new tab at end of window 1 with properties {URL:\"$1\"}" >/dev/null
  CREATED_WINDOW=1
  CREATED_INDEX="$(osascript -e 'tell application "Safari" to return (count of tabs of window 1)')"
  OUR_TAB_URL="echo360.net.au/courses"
  CREATED_TAB=1
}

close_our_tab() {
  [ "$CREATED_TAB" -eq 1 ] || return 0
  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Safari"
  if (count of windows) < $CREATED_WINDOW then return
  if (count of tabs of window $CREATED_WINDOW) < $CREATED_INDEX then return
  if (URL of tab $CREATED_INDEX of window $CREATED_WINDOW as string) contains "$OUR_TAB_URL" then
    close tab $CREATED_INDEX of window $CREATED_WINDOW
  end if
end tell
APPLESCRIPT
}
release_safari() {
  eval_js 'window.__dl = null; window.__echo = null; "ok"' >/dev/null 2>&1 || true
  close_our_tab
  CREATED_TAB=0
}

trap 'rm -rf "$TMP"; close_our_tab' EXIT

FAST=0
argv=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --fast) FAST=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--fast] [UNIT_CODE]"
      echo
      echo "  UNIT_CODE  e.g. CITS2211. Omit it to use the Echo360 page already"
      echo "             open in Safari."
      echo "  --fast     Transcribe with $FAST_MODEL."
      echo "             Roughly twice as quick, but it misspells subject"
      echo "             vocabulary, so the transcripts search poorly. Use it"
      echo "             for a rough read, not for the notes you keep."
      exit 0 ;;
    --) shift; argv+=(${@+"$@"}); break ;;
    -*) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    *) argv+=("$1") ;;
  esac
  shift
done
set -- ${argv[@]+"${argv[@]}"}

if [ "$FAST" -eq 1 ]; then
  MODEL="$FAST_MODEL"
fi

for tool in zip parakeet-mlx ffmpeg osascript; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing tool: $tool"
    echo "Install what you need with:"
    echo "  brew install ffmpeg"
    echo "  pip install parakeet-mlx"
    exit 1
  fi
done

if [ "$#" -ge 1 ]; then
  WANT="$1"
  echo "Looking up $WANT on the courses page..."
  open_tab "https://echo360.net.au/courses"
  sleep 5

  printf 'window.__unit = "%s";\n' "$WANT" > "$TMP/find.js"
  cat "$HERE/safari-find-section.js" >> "$TMP/find.js"

  FOUND="$(run_js "$TMP/find.js" "echo360.net.au/courses" 2>&1 || true)"
  case "$FOUND" in
    *"Allow JavaScript from Apple Events"*)
      echo
      echo "Safari will not let scripts run in the page yet."
      echo "Turn it on once: Safari > Develop menu > Allow JavaScript from Apple Events."
      exit 1 ;;
    *NO_TAB*)
      echo "Could not open the Echo360 courses page in Safari."
      exit 1 ;;
  esac

  for _ in $(seq 1 30); do
    sleep 1
    FSTATUS="$(eval_js 'window.__find.status' 'echo360.net.au/courses')"
    [ "$FSTATUS" = "done" ] && break
    if [ "$FSTATUS" = "notfound" ]; then
      echo
      echo "Echo360 has no course matching \"$WANT\" for your account."
      echo "Check the code, or open the unit in Safari and run this with no arguments."
      exit 1
    fi
    case "$FSTATUS" in error|timeout)
      echo "Could not search the courses page ($FSTATUS)."
      exit 1 ;;
    esac
  done

  if [ "${FSTATUS:-}" != "done" ]; then
    echo "Timed out searching the courses page."
    exit 1
  fi

  HREF="$(eval_js 'window.__find.href' 'echo360.net.au/courses')"
  LABEL="$(eval_js 'window.__find.label' 'echo360.net.au/courses')"
  echo "Found: $LABEL"

  MATCH="${HREF%/home}"
  OUR_TAB_URL="$MATCH"
  osascript <<APPLESCRIPT >/dev/null
tell application "Safari"
  set URL of tab $CREATED_INDEX of window $CREATED_WINDOW to "https://echo360.net.au$HREF"
end tell
APPLESCRIPT
  sleep 4
fi

echo "Reading the lecture list from Safari..."
OUT_JS="$(run_js "$HERE/safari-manifest.js" 2>&1 || true)"

case "$OUT_JS" in
  *"Allow JavaScript from Apple Events"*)
    echo
    echo "Safari will not let scripts run in the page yet."
    echo "Turn it on once: Safari > Develop menu > Allow JavaScript from Apple Events."
    echo "(If there is no Develop menu: Settings > Advanced > Show features for web developers.)"
    exit 1 ;;
  *NO_TAB*|*NO_SECTION_TAB*)
    echo
    echo "No Echo360 section page is open in Safari."
    echo "Open the unit's home page - its address contains /section/ - and run this again."
    exit 1 ;;
  *"Application isn't running"*|*"-600"*)
    echo
    echo "Safari does not seem to be running. Open it on the unit's section page."
    exit 1 ;;
esac

for _ in $(seq 1 30); do
  sleep 1
  STATUS="$(eval_js 'window.__echo ? window.__echo.status : "missing"')"
  [ "$STATUS" = "done" ] && break
  if [ "$STATUS" = "error" ]; then
    echo "Could not read the syllabus: $(eval_js 'window.__echo.error')"
    exit 1
  fi
done

if [ "${STATUS:-}" != "done" ]; then
  echo "Timed out reading the syllabus from the page."
  exit 1
fi

UNIT="$(eval_js 'window.__echo.prefix')"
COUNT="$(eval_js 'String(window.__echo.count)')"
OUT="$BASE/$UNIT"

vault_matches=()
for d in "$VAULT"/*_"$UNIT"; do
  [ -d "$d" ] && vault_matches+=("$d")
done

if [ "${#vault_matches[@]}" -eq 0 ]; then
  echo
  echo "No Obsidian project folder for $UNIT."
  echo "Expected a directory ending in _$UNIT under:"
  echo "  $VAULT"
  echo
  echo "Create one (for example ${VAULT}/001_uni_compsci_${UNIT}) and run this again."
  echo "Nothing has been downloaded."
  exit 1
fi

VAULT_DIR="${vault_matches[0]}"
if [ "${#vault_matches[@]}" -gt 1 ]; then
  echo "Several vault folders end in _$UNIT; using $(basename "$VAULT_DIR")."
fi
TRANSCRIPTS="$VAULT_DIR/transcripts"

echo "Unit:        $UNIT ($COUNT recordings)"
echo "Audio:       $OUT"
echo "Transcripts: $TRANSCRIPTS"
echo

mkdir -p "$OUT" "$TRANSCRIPTS"

eval_js 'window.__echo.rows.join("\n")' > "$TMP/rows.tsv"

skip=()
while IFS=$'\t' read -r name _; do
  [ -z "$name" ] && continue
  if [ -f "$TRANSCRIPTS/${name%.mp3}.md" ]; then
    echo "Skip (already transcribed): $name"
    skip+=("$name")
  elif [ -f "$OUT/$name" ]; then
    echo "Skip (already downloaded):  $name"
    skip+=("$name")
  fi
done < "$TMP/rows.tsv"

while IFS=$'\t' read -r name _; do
  [ -z "$name" ] && continue
  if [ -f "$DOWNLOADS/$name" ] && [ ! -f "$OUT/$name" ]; then
    mv "$DOWNLOADS/$name" "$OUT/$name"
    echo "Recovered from Downloads:   $name"
  fi
done < "$TMP/rows.tsv"

{
  printf 'window.__skip = ['
  first=1
  for s in ${skip[@]+"${skip[@]}"}; do
    [ "$first" -eq 1 ] || printf ','
    printf '"%s"' "$s"
    first=0
  done
  printf '];\n'
  cat "$HERE/safari-download.js"
} > "$TMP/download.js"

TODO=$(( COUNT - ${#skip[@]} ))
if [ "$TODO" -le 0 ]; then
  echo
  echo "Nothing new to download."
else
  echo
  echo "Downloading $TODO file(s) through Safari (this is the slow part)..."
  run_js "$TMP/download.js" >/dev/null

  last=""
  while :; do
    sleep 3
    DSTATUS="$(eval_js 'window.__dl.status')"
    CURRENT="$(eval_js 'window.__dl.current || ""')"
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$last" ]; then
      echo "  fetching $CURRENT"
      last="$CURRENT"
    fi
    [ "$DSTATUS" = "done" ] && break
    if [ "$DSTATUS" = "error" ]; then
      echo "  Download stopped: $(eval_js 'window.__dl.error')"
      break
    fi
  done

  eval_js 'window.__dl.done.join("\n")' | while IFS=$'\t' read -r name bytes; do
    [ -z "$name" ] && continue
    echo "  ok   $name ($(( bytes / 1048576 )) MB)"
  done

  FAILED="$(eval_js 'window.__dl.failed.join("\n")')"
  if [ -n "$FAILED" ]; then
    echo
    echo "These failed:"
    printf '%s\n' "$FAILED" | sed 's/^/  /'
    echo "Run the script again to retry them; everything else is kept."
  fi
fi

while IFS=$'\t' read -r name _; do
  [ -z "$name" ] && continue
  [ -f "$DOWNLOADS/$name" ] || continue
  prev=0
  for _ in $(seq 1 60); do
    size="$(stat -f%z "$DOWNLOADS/$name" 2>/dev/null || echo 0)"
    [ "$size" -gt 0 ] && [ "$size" = "$prev" ] && break
    prev="$size"
    sleep 1
  done
  mv "$DOWNLOADS/$name" "$OUT/$name"
done < "$TMP/rows.tsv"

release_safari

cd "$OUT"

todo=()
for f in *.mp3; do
  if [ -f "$TRANSCRIPTS/${f%.mp3}.md" ]; then
    echo "Skip (already transcribed): $f"
  else
    todo+=("$f")
  fi
done

if [ "${#todo[@]}" -gt 0 ]; then
  echo
  if [ "$FAST" -eq 1 ]; then
    echo "Transcribing ${#todo[@]} file(s) in --fast mode ($(basename "$MODEL"))."
    echo "Expect misspelled subject terms; these will search poorly in Obsidian."
  else
    echo "Transcribing ${#todo[@]} file(s) with parakeet-mlx (this is the slow part)..."
  fi
  parakeet-mlx "${todo[@]}" \
    --model "$MODEL" \
    --chunk-duration "$CHUNK" \
    --output-format txt \
    --output-dir "$TRANSCRIPTS"

  for f in ${todo[@]+"${todo[@]}"}; do
    t="$TRANSCRIPTS/${f%.mp3}.txt"
    if [ -f "$t" ]; then
      mv "$t" "${t%.txt}.md"
    fi
  done

  silent=()
  for f in ${todo[@]+"${todo[@]}"}; do
    md="$TRANSCRIPTS/${f%.mp3}.md"
    if [ -f "$md" ] && [ ! -s "$md" ]; then
      echo "No speech was found in this recording - the source audio is silent." > "$md"
      silent+=("${f%.mp3}")
    fi
  done
  if [ "${#silent[@]}" -gt 0 ]; then
    echo
    echo "Produced no text (the source audio is silent):"
    printf '  %s\n' "${silent[@]}"
  fi
else
  echo
  echo "Nothing new to transcribe."
fi

loose=(*.mp3)
if [ "${#loose[@]}" -gt 0 ]; then
  echo
  echo "Zipping ${#loose[@]} original audio file(s) into original_audios.zip..."
  zip -0 -jm original_audios.zip "${loose[@]}"
fi

echo
echo "Done."
echo "  Transcripts: $TRANSCRIPTS"
echo "  Audio:       $OUT/original_audios.zip"
