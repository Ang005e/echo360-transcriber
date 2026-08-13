#!/usr/bin/env bash
#
# get-lectures.sh
#
# Downloads Echo360 lecture audio and transcribes it locally with parakeet-mlx.
#
# Open the unit's Echo360 section page in Safari (the page whose address
# contains "/section/..."), then run this. That is the whole setup - it uses the
# Safari session you are already signed into, so there is no second browser, no
# login, and no cookies to copy.
#
# How it works: AppleScript runs a small script inside that Safari page. The
# page reads the syllabus, then fetches the audio itself and hands each file to
# Safari as a download. Requests from the page carry your session automatically,
# which is why no cookie ever has to be extracted.
#
# One-off setup: Safari's Develop menu must be on, and within it
# "Allow JavaScript from Apple Events" must be ticked. The script says so if it
# is not.
#
# It will:
#   - read the lecture list from the section page open in Safari,
#   - download anything not already transcribed, into transcriptions/<UNIT>/,
#   - transcribe each one into the unit's Obsidian project folder, under
#     1_Projects/<something>_<UNIT>/transcripts/,
#   - zip the original audio into original_audios.zip.
#
# The Obsidian project folder has to exist already. If there is no directory
# ending in the unit code, this stops before downloading anything rather than
# leaving the transcripts somewhere you did not ask for.
#
# Lectures that already have a .md in the transcripts folder are skipped and
# are never re-downloaded, so running this repeatedly to pick up new lectures is
# both safe and cheap.
#
# Usage:
#   ./get-lectures.sh CITS1402   finds that unit itself, via the courses page
#   ./get-lectures.sh            uses whichever section page is open in Safari

set -eu
shopt -s nullglob

# ----- settings you can change ----------------------------------------------
BASE="/Users/angusblakeuni/Documents/transcriptions"   # audio downloads + zip
DOWNLOADS="$HOME/Downloads"                            # where Safari saves
VAULT="$HOME/Obsidian/MyVault/1_Projects"              # obsidian project folders
MODEL="mlx-community/parakeet-tdt-0.6b-v3"
# ----------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"

# Which tab we are driving. Narrowed to one exact section id as soon as we know
# it, so other Echo360 tabs left open cannot be picked up by mistake.
MATCH="/section/"
CREATED_TAB=0
CREATED_WINDOW=1
CREATED_INDEX=0
OUR_TAB_URL=""

# --- run a javascript file in the Safari tab we are driving ------------------
# Takes the last matching tab: a tab this script opened is appended at the end,
# so it wins over any the user already had open.
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

# Reads a value out of the page, e.g. eval_js 'window.__echo.prefix'
eval_js() {
  printf '%s' "$1" > "$TMP/eval.js"
  run_js "$TMP/eval.js" "${2:-$MATCH}"
}

open_tab() {
  osascript -e "tell application \"Safari\" to make new tab at end of window 1 with properties {URL:\"$1\"}" >/dev/null
  # Remember exactly which tab is ours. Closing by URL alone is not safe: the
  # user may have their own tab open on the same page, and on the not-found path
  # we would otherwise go hunting for a section tab we never opened.
  CREATED_WINDOW=1
  CREATED_INDEX="$(osascript -e 'tell application "Safari" to return (count of tabs of window 1)')"
  OUR_TAB_URL="echo360.net.au/courses"
  CREATED_TAB=1
}

# Closing is deliberately timid. Tab indices shift if the user opens or closes
# tabs while this runs, so we only close when the tab still sitting at our index
# is the page we put there. If it is not, we leave it alone - a stray tab is a
# far better outcome than closing something of the user's.
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
trap 'rm -rf "$TMP"; close_our_tab' EXIT

# --- 1. check the tools are installed ---------------------------------------
for tool in zip parakeet-mlx ffmpeg osascript; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing tool: $tool"
    echo "Install what you need with:"
    echo "  brew install ffmpeg"
    echo "  pip install parakeet-mlx"
    exit 1
  fi
done

# --- 2. if a unit was named, find its section page ourselves ----------------
# The course grid renders lazily, so this drives the page's own search box
# instead of hoping the unit happens to be on screen.
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

  # From here on, drive exactly this section and nothing else.
  MATCH="${HREF%/home}"
  OUR_TAB_URL="$MATCH"
  # Only ever navigate the tab we opened. Retargeting every courses tab would
  # yank the user's own tab out from under them.
  osascript <<APPLESCRIPT >/dev/null
tell application "Safari"
  set URL of tab $CREATED_INDEX of window $CREATED_WINDOW to "https://echo360.net.au$HREF"
end tell
APPLESCRIPT
  sleep 4
fi

# --- 3. read the lecture list out of the page -------------------------------
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

# The manifest is built asynchronously; wait for it to land.
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

# --- where the transcripts belong -------------------------------------------
# The vault folder for a unit is whichever project directory ends with the unit
# code, e.g. 001_uni_compsci_ELEC1303 for ELEC1303. This is resolved before
# anything is downloaded: finding out at the end that there is nowhere to put
# the transcripts, after pulling down gigabytes of audio, would be no use.
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

# --- 4. work out what can be skipped ----------------------------------------
# Anything already transcribed, and anything already sitting in the audio
# folder, does not need fetching again. These files are large, so this matters.
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

# A same-named leftover in Downloads would make Safari save "name (1).mp3", so
# move any stragglers into place first.
while IFS=$'\t' read -r name _; do
  [ -z "$name" ] && continue
  if [ -f "$DOWNLOADS/$name" ] && [ ! -f "$OUT/$name" ]; then
    mv "$DOWNLOADS/$name" "$OUT/$name"
    echo "Recovered from Downloads:   $name"
  fi
done < "$TMP/rows.tsv"

# --- 5. let the page download whatever is left ------------------------------
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

# --- 6. move the downloads into place ---------------------------------------
# Safari writes to Downloads. Wait for each file to stop growing before moving,
# so a partial file never gets transcribed.
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

cd "$OUT"

# --- 7. transcribe ----------------------------------------------------------
# Only transcribe files that do not already have a transcript. A previous run
# that was interrupted after downloading leaves loose .mp3 files behind, so we
# cannot just transcribe everything in the folder.
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
  echo "Transcribing ${#todo[@]} file(s) with parakeet-mlx (this is the slow part)..."
  parakeet-mlx "${todo[@]}" \
    --model "$MODEL" \
    --local-attention \
    --output-format txt \
    --output-dir "$TRANSCRIPTS"

  # parakeet-mlx cannot emit markdown, and Obsidian only indexes .md as notes -
  # a .txt transcript would sit in the vault unsearchable. So rename them.
  for t in "$TRANSCRIPTS"/*.txt; do
    mv "$t" "${t%.txt}.md"
  done

  # A recording with no sound in it - Echo360 does produce those - transcribes
  # to an empty file. Left at zero bytes it would be skipped by every later run
  # with nothing to say why, so write the reason into the note instead. It still
  # counts as done, which is right: re-fetching 90 MB of silence would achieve
  # nothing.
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


# --- 8. zip the original audio and remove the loose files -------------------
# Anything still loose here is now transcribed, so it is safe to archive.
loose=(*.mp3)
if [ "${#loose[@]}" -gt 0 ]; then
  echo
  echo "Zipping ${#loose[@]} original audio file(s) into original_audios.zip..."
  zip -jm original_audios.zip "${loose[@]}"
fi

echo
echo "Done."
echo "  Transcripts: $TRANSCRIPTS"
echo "  Audio:       $OUT/original_audios.zip"
