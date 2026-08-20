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

## Signing in

Echo360 sessions lapse long before the university's Microsoft one does. When
that happens the courses page redirects to a login form that wants an email
address and nothing else - Safari's own Microsoft cookie carries the rest - so
the script fills it in and waits for the redirect back.

The email is `25166813@student.uwa.edu.au`, set as `ECHO_EMAIL` at the top of
`get-lectures.sh` and overridable per run:

```zsh
ECHO_EMAIL=someone@example.edu ./get-lectures.sh CITS1402
```

No password is stored or typed. If Microsoft asks for one - or for a passkey or
an MFA approval - the run stops with "Microsoft is asking for more than an email
address" and downloads nothing. Sign in to Echo360 in Safari by hand once, and
the next run goes through on its own.

This only applies when a unit code is given. Run with no arguments and the
section page you already have open is used as-is.

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

## Using it from Claude Desktop

`mcp-server.py` exposes the pipeline to Claude Desktop as an MCP server. It is
one standard-library Python file run by `/usr/bin/python3` - no virtualenv, no
packages to install, nothing to keep up to date. Idle, it is a process blocked
on a read.

It is registered in
`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
"echo360-transcriber": {
  "command": "/usr/bin/python3",
  "args": ["/Users/angusblakeuni/Projects/Utilities/echo360-transcriber/mcp-server.py"]
}
```

Three tools:

- `update_transcripts(unit, fast)` - runs `get-lectures.sh`. It returns straight
  away and the run continues in the background, because transcribing a semester
  takes far longer than a tool call should wait. The run also survives quitting
  Claude Desktop.
- `run_status(tail)` - whether the run is going, how long it has taken, and the
  end of its log.
- `list_transcripts(unit)` - what is already in the vault.

Only one run at a time: `update_transcripts` refuses while another is going,
since two models at once will not fit in memory.

Logs and run state live in `~/Library/Logs/echo360-transcriber/`.

Safari must be running. The first time Claude Desktop starts a run, macOS asks
whether Claude may control Safari - this is a separate permission from the one
Terminal was granted, and the run fails until it is allowed. If it was denied,
re-enable it under **System Settings > Privacy & Security > Automation >
Claude > Safari**.

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
- A failed sign-in deliberately leaves the login tab open, so you can finish it
  by hand and run again.
- The course code and institution id are read from the page's own data, so this
  works for any unit at any institution without editing.
- `console-snippet.js` pasted into the browser console on a section page
  produces the `.tsv` list, as a manual fallback.
- `MODEL`, `FAST_MODEL`, `CHUNK`, `VAULT` and the audio folder are set at the top
  of `get-lectures.sh`.
- `CHUNK` is how many seconds of audio go through the model at once, currently
  480, paired with `--local-attention`. Encoder attention cost grows with the
  square of the chunk length, so long chunks need local attention to stay within
  memory. Measured on an M2/8GB: 480 with local attention transcribes about 24%
  faster than 120 with full attention, with no loss of subject vocabulary.

## Where to keep it

Keep the folder at `~/Projects/Utilities/echo360-transcriber/`, with an alias in
`~/.zshrc`:

```zsh
alias get-lectures="~/Projects/Utilities/echo360-transcriber/get-lectures.sh"
```

After `source ~/.zshrc`, `get-lectures CITS1402` works from any directory.
