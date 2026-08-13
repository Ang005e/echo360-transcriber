// console-snippet.js
//
// Run this in the Safari Web Inspector console while you are on the Echo360
// SECTION HOME PAGE for the unit you want (the page whose address contains
// "/section/<some-id>").
//
// It reads the syllabus, works out a clean filename for every recording -
// lecture, tutorial, workshop or otherwise - and saves <UNIT>_audio.tsv into
// your Downloads folder.
// That file is the only thing the terminal script needs.
//
// Nothing here is specific to one unit. The course code and the institution id
// are both read from the page's own data, so the same snippet works for any
// unit at any institution without editing.
//
// It does NOT download the audio itself — the browser is not allowed to read
// the audio bytes directly. The terminal script does that part.

(async function () {
  var mon = {Jan:'01',Feb:'02',Mar:'03',Apr:'04',May:'05',Jun:'06',
             Jul:'07',Aug:'08',Sep:'09',Oct:'10',Nov:'11',Dec:'12'};

  // What kind of session a recording is, read out of the lesson name - Echo360
  // records it there and nowhere else ("... - Lecture", "CITS2211 Tutorial").
  // Leftmost keyword wins, so "Lecture 3 - lab demo" stays a lecture. Word
  // boundaries matter: a bare "lab" must not match inside "collaborative".
  var KIND_RE = /\b(lectures?|tutorials?|tuts?|workshops?|seminars?|practicals?|pracs?|labs?|revisions?)\b/i;
  var KIND_ALIAS = {tut: 'tutorial', prac: 'practical'};
  function kindOf(name) {
    var hit = name.match(KIND_RE);
    if (!hit) return 'lecture';           // unchanged default for odd names
    var k = hit[1].toLowerCase().replace(/s$/, '');
    return KIND_ALIAS[k] || k;
  }

  // The date a recording belongs to. Only some lesson names carry one -
  // "CITS2211 Tutorial" has none - so read the scheduled time out of the
  // syllabus instead, which every lesson has, and keep the name and the
  // position as fallbacks. startTimeUTC is UTC and captureStartedAt is local
  // wall time; both end up as the local calendar date.
  function dateOf(entry, name, i) {
    var t = entry.lesson.startTimeUTC || entry.lesson.captureStartedAt;
    var d = t ? new Date(t) : null;
    if (d && !isNaN(d.getTime())) {
      return d.getFullYear() + '-' +
             ('0' + (d.getMonth() + 1)).slice(-2) + '-' +
             ('0' + d.getDate()).slice(-2);
    }
    var dm = name.match(/(\d{1,2}) (\w{3}) (\d{4})/);
    return dm
      ? dm[3] + '-' + (mon[dm[2]] || '00') + '-' + ('0' + dm[1]).slice(-2)
      : String(i + 1).padStart(2, '0');
  }

  var m = location.pathname.match(/\/section\/([a-f0-9-]{36})/);
  if (!m) {
    console.log('You are not on a section page. Open the unit home page first.');
    return;
  }
  var sectionId = m[1];

  console.log('Fetching syllabus...');
  var r = await fetch('/section/' + sectionId + '/syllabus', {credentials: 'include'});
  var json = await r.json();

  var lessons = (json.data || []).filter(function (it) {
    return it.type === 'SyllabusLessonType' && it.lesson && it.lesson.hasContent;
  });
  console.log('Lessons with content: ' + lessons.length);
  if (!lessons.length) { console.log('Nothing found. Nothing saved.'); return; }

  // Course code, e.g. "CITS1003", taken from the first lesson name. Derived,
  // never hardcoded.
  var prefix = ((lessons[0].lesson.lesson.name || '').match(/^([A-Z0-9]+)/) || ['', 'lesson'])[1];

  // Institution id, read from the page data instead of being hardcoded.
  // Echo360 stamps it into every content/thumbnail URL as "0000.<id>", and
  // also exposes it in "institutionId" fields. We take whichever shows up
  // first. This is only needed as a fallback for building a URL (see below).
  var whole = JSON.stringify(json);
  var inst = (whole.match(/0000\.([0-9a-f-]{36})/) ||
              whole.match(/"institutionId"\s*:\s*"([0-9a-f-]{36})"/) ||
              [])[1];

  var lines = [];
  var seen = {};      // base name -> how many lessons have claimed it
  for (var i = 0; i < lessons.length; i++) {
    var name = lessons[i].lesson.lesson.name || '';
    var medias = lessons[i].lesson.medias || [];

    var date = dateOf(lessons[i], name, i);
    var kind = kindOf(name);

    for (var j = 0; j < medias.length; j++) {
      var sfx = medias.length > 1 ? '_' + (j + 1) : '';

      // Two recordings can legitimately land on the same day and kind - a
      // re-upload alongside the original, say - and one silently overwriting
      // the other's transcript would be the worst outcome. Later ones get a
      // counter; the first keeps the clean name.
      var base = prefix + '_' + date + '_' + kind + sfx;
      seen[base] = (seen[base] || 0) + 1;
      var filename = base + (seen[base] > 1 ? '_' + seen[base] : '') + '.mp3';

      // Prefer the real audio URL if the syllabus data already carries it.
      // Otherwise build the exact path Echo360 uses (this construction was
      // confirmed against a captured media response: the media id drops
      // straight into the path).
      var found = (JSON.stringify(medias[j])
        .match(/https:\/\/content\.echo360\.net\.au\/[^"'\\]*?\/audio\.mp3/) || [])[0];
      var url = found ||
        (inst ? 'https://content.echo360.net.au/0000.' + inst + '/' + medias[j].id + '/1/audio.mp3'
              : null);

      if (!url) {
        console.log('No URL for ' + filename + ' (could not find an institution id).');
        continue;
      }
      lines.push(filename + '\t' + url);
    }
    console.log('#' + (i + 1) + ' ' + name + ' -> ' + medias.length + ' media');
  }

  if (!lines.length) { console.log('No audio URLs built. Nothing saved.'); return; }

  var tsv = lines.join('\n') + '\n';
  var blob = new Blob([tsv], {type: 'text/tab-separated-values'});
  var a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = prefix + '_audio.tsv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(a.href);

  console.log('\nSaved ' + prefix + '_audio.tsv (' + lines.length + ' files) to your Downloads folder.');
  console.log('Now run get-lectures.sh in the terminal.');
})();
