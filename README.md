# echo360-transcriber

Downloads Echo360 lecture audio for a unit and transcribes it locally with
`parakeet-mlx`, into an Obsidian vault.

## What it produces

```
~/Obsidian/MyVault/1_Projects/001_uni_compsci_ELEC1303/transcripts/
  ELEC1303_2026-07-21_lecture.md
  ELEC1303_2026-07-22_tutorial.md
  ELEC1303_2026-07-23_workshop.md
  ...

~/Documents/transcriptions/ELEC1303/
  original_audios.zip
```

Transcripts are `.md`. The source audio is zipped after transcription.

Filenames are `UNIT_DATE_KIND.md`. The kind comes from the recording's name in
Echo360: `lecture`, `tutorial`, `workshop`, `seminar`, `practical`, `lab` or
`revision`, with `tut` and `prac` read as the full words. Where a name matches
more than one, the first wins. Names matching none become `lecture`.

The date is the recording's scheduled start from the syllabus, as a local
calendar date. A recording with several media files gets a `_1`, `_2` suffix per
file; a name that collides with one already generated gets a further `_2`.

A recording whose audio is silent produces a note saying so, and is listed at
the end of the run.

The vault folder for a unit is whichever directory under `1_Projects` ends with
the unit code. The `transcripts` subfolder is created if absent. The project
folder must already exist — if nothing matches, the run stops before fetching
any audio.

Anything that already has a `.md` in the transcripts folder is skipped: not
re-downloaded, not re-transcribed, not overwritten.

## Requirements

- A Mac with Apple Silicon
- Safari, signed in to Echo360
- `brew install ffmpeg`
- `pip install parakeet-mlx`

## One-off setup

1. **Settings → Advanced → Show features for web developers** (adds the Develop
   menu).
2. **Develop → Allow JavaScript from Apple Events.**

On first run, macOS asks whether Terminal may control Safari. The script reports
if either is missing.

## How to run it

```zsh
./get-lectures.sh CITS1402
```

It finds the unit on the Echo360 courses page, opens it in a background tab,
reads the lecture list, downloads whatever isn't already transcribed,
transcribes it, zips the originals, and closes the tab it opened.

With the unit's section page already open in Safari, the unit code can be left
off:

```zsh
./get-lectures.sh
```

`--fast` selects `FAST_MODEL`, which transcribes about twice as quickly and
misspells subject vocabulary:

```zsh
./get-lectures.sh --fast CITS1402
```

Fast-mode transcripts are written to the same filenames as normal ones, and are
skipped by later runs the same way.

## How it works

The audio sits behind CloudFront and needs three signed cookies. They are
`HttpOnly` session cookies, so scripts cannot read them and they are not written
to disk.

The cookies are never read. AppleScript runs a script inside the Echo360 page
already signed in, and the page does the work:

- `safari-find-section.js` drives the courses page's search box to find the unit
  and its section URL.
- `safari-manifest.js` reads the syllabus and derives a filename and audio URL
  for every recording.
- `safari-download.js` fetches each audio file and hands it to Safari as a
  download.

Requests made by the page carry the session automatically. `content.echo360.net.au`
serves the audio CORS-readable, so the page reads the bytes back and saves them.

## Notes and troubleshooting

- `parakeet-mlx` emits `.txt`; the script renames its output to `.md`, which is
  what Obsidian indexes as notes.
- Only `1_Projects` is searched. Units under `4_Archive` stop with "no project
  folder".
- Re-running after a failure skips anything already downloaded or transcribed.
- "Safari will not let scripts run in the page yet" — the *Allow JavaScript from
  Apple Events* checkbox is off.
- "Echo360 has no course matching X" — the unit isn't in your Echo360 course
  list. Check the code, or open the unit in Safari and run with no arguments.
- "No Obsidian project folder for X" — create a directory ending in that unit
  code under `1_Projects` and run again. Nothing is downloaded until then.
- Closing or opening Safari tabs mid-run can leave the tab it opened behind.
- The course code and institution id are read from the page's own data, so this
  works for any unit at any institution without editing.
- `console-snippet.js` pasted into the browser console on a section page
  produces the `.tsv` list, as a manual fallback.
- `MODEL`, `FAST_MODEL`, `CHUNK`, `VAULT` and the audio folder are set at the top
  of `get-lectures.sh`.
- `CHUNK` is how many seconds of audio go through the model at once, currently
  480.

## Where to keep it

Keep the folder at `~/Projects/Utilities/echo360-transcriber/`, with an alias in
`~/.zshrc`:

```zsh
alias get-lectures="~/Projects/Utilities/echo360-transcriber/get-lectures.sh"
```

After `source ~/.zshrc`, `get-lectures CITS1402` works from any directory.
