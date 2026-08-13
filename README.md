# echo360-transcriber

Downloads Echo360 lecture audio for a unit and makes good-quality transcripts
locally with `parakeet-mlx`, for indexing and semantic search in Obsidian.

I use this because the transcripts Echo360 provides are low quality. This grabs
the original audio instead and transcribes it myself.

## What it produces

Transcripts go straight into the unit's Obsidian project folder, and the source
audio is archived separately (ELEC1303 shown as an example; the unit name comes
from whatever course you point it at):

```
~/Obsidian/MyVault/1_Projects/001_uni_compsci_ELEC1303/transcripts/
  ELEC1303_2026-07-21_lecture.md
  ELEC1303_2026-07-22_tutorial.md
  ELEC1303_2026-07-23_workshop.md
  ...

~/Documents/transcriptions/ELEC1303/
  original_audios.zip      (the source audio, zipped after transcription)
```

The kind of session comes from the recording's own name in Echo360 — `lecture`,
`tutorial`, `workshop`, `seminar`, `practical`, `lab` or `revision`, with `tut`
and `prac` read as the full words. Where a name has more than one of them, the
first wins, so "Lecture 3 — lab demo" is a lecture. Names with none of them fall
back to `lecture`.

The date is the recording's scheduled start from the syllabus, as a local
calendar date. It deliberately does **not** come from the recording's name: only
some names carry a date, and the ones that don't — "CITS2211 Tutorial" — would
otherwise be numbered by position and shift whenever the syllabus changes. If
two recordings land on the same date and kind, the second gets a `_2` suffix
rather than overwriting the first.

A recording whose audio is silent transcribes to nothing. Rather than leave a
0-byte note that every later run skips without explanation, the note is written
with a line saying the source audio was silent, and the run reports it at the
end.

The vault folder for a unit is whichever project directory **ends with the unit
code** — `001_uni_compsci_ELEC1303` for `ELEC1303`. The `transcripts` subfolder
is created if it isn't there, but **the project folder itself must already
exist**: if nothing matches, the run stops with a message and downloads nothing,
rather than putting transcripts somewhere you didn't ask for. That check happens
before any audio is fetched.

Re-running for the same unit is safe and is the normal way to pick up new
lectures. Anything that already has a `.md` in the transcripts folder is
skipped — not re-downloaded, not re-transcribed, and never overwritten. Since
lectures run to about 90 MB each, that matters.

## Requirements

- A Mac with Apple Silicon
- Safari, signed in to Echo360 as normal
- `brew install ffmpeg`
- `pip install parakeet-mlx`

No second browser, no login, no cookie wrangling.

## One-off setup

Safari has to let a script run inside the page. Two checkboxes, once:

1. **Settings → Advanced → Show features for web developers** (this adds the
   Develop menu).
2. **Develop → Allow JavaScript from Apple Events.**

The first time it runs, macOS will also ask whether Terminal may control
Safari. Say yes. The script tells you if either of these is missing.

## How to run it

```zsh
./get-lectures.sh CITS1402
```

That's the whole thing. It finds the unit on your Echo360 courses page, opens
it in a background tab, reads the lecture list, downloads whatever isn't already
transcribed, transcribes it, and zips the originals. The tab it opened is closed
afterwards.

If you already have the unit's section page open in Safari, you can leave the
unit off and it will use that page:

```zsh
./get-lectures.sh
```

## How it works

The awkward part of Echo360 is that the audio sits behind CloudFront and needs
three signed cookies. Those cookies are `HttpOnly`, so no script can read them —
which is what makes "just grab the cookies" approaches fail. Safari does not
write them to disk either, since they are session cookies, so they cannot be
lifted out of the cookie jar. Reading them out of Safari at all turns out to be
impossible without an unsupported debugger channel.

None of that matters, because the cookies never have to be read. AppleScript
runs a small script inside the Echo360 page you are already signed into, and
that page does the work itself:

- `safari-find-section.js` drives the courses page's own search box to find the
  unit and its section URL. (The course grid renders lazily, so searching is
  more reliable than scraping whatever happens to be on screen.)
- `safari-manifest.js` reads the syllabus and derives a filename and audio URL
  for every recording.
- `safari-download.js` fetches each audio file and hands it to Safari as a
  download.

Requests made by the page carry the session automatically — `HttpOnly` stops
scripts *reading* cookies, not the browser *sending* them. And
`content.echo360.net.au` serves the audio CORS-readable, so the page can read
the bytes back and save them. That combination is why no cookie, no second
browser, and no login is needed anywhere.

## Notes and troubleshooting

- Transcripts are written as **`.md`**, not `.txt`. Obsidian only indexes
  markdown as notes, so a `.txt` would sit in the vault unsearchable.
  `parakeet-mlx` can't emit markdown, so the script renames its output.
- Only `1_Projects` is searched. Units filed under `4_Archive` will stop with
  "no project folder" — move the folder back if you want to fetch for them.
- The script is **resumable**. It skips anything already downloaded or already
  transcribed, so re-running after any failure is safe and cheap.
- "Safari will not let scripts run in the page yet" means the *Allow JavaScript
  from Apple Events* checkbox above is off.
- "Echo360 has no course matching X" means exactly that — the unit isn't in your
  Echo360 course list. Check the code, or open the unit in Safari and run with
  no arguments.
- If you open or close Safari tabs while it runs, the tab it opened may be left
  behind rather than closed. That is deliberate: it would rather leave a stray
  tab than risk closing one of yours.
- Nothing is tied to one unit. The course code (e.g. `CITS1402`, `CITS1003`) and
  the institution id are both read from the page's own data, so this works for
  any unit at any institution with no editing.
- `console-snippet.js` is kept as a manual fallback. Pasting it into the browser
  console on a section page still produces the `.tsv` list, which is useful if
  the automated path ever breaks.
- "No Obsidian project folder for X" means there is no directory ending in that
  unit code under `1_Projects`. Create one — the naming is yours, only the
  ending matters — and run again. Nothing is downloaded until that resolves.
- The transcription model, the vault location (`VAULT`) and the audio folder are
  all set near the top of `get-lectures.sh`.

## Where to keep it

Keep the folder at `~/Projects/Utilities/echo360-transcriber/`, and add an alias to
`~/.zshrc` so you can run it from anywhere:

```zsh
alias get-lectures="~/Projects/Utilities/echo360-transcriber/get-lectures.sh"
```

Then `source ~/.zshrc` once. After that, `get-lectures CITS1402` from any
directory is the whole workflow.
