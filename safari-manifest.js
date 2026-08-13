// safari-manifest.js
//
// Runs inside the Echo360 section page in Safari, via AppleScript's
// "do JavaScript". Reads the syllabus and works out a clean filename and an
// audio URL for every recording - lecture, tutorial, workshop or otherwise -
// leaving the result on window.__echo for the shell script to read back.
//
// This is the same derivation console-snippet.js uses, so filenames stay
// identical to transcripts already on disk. The difference is that nothing
// gets saved here and nobody has to paste anything - get-lectures.sh drives it.
//
// Nothing is specific to one unit: the course code and the institution id both
// come from the page's own data.

window.__echo = {status: 'running'};

(async function () {
  try {
    var mon = {Jan:'01',Feb:'02',Mar:'03',Apr:'04',May:'05',Jun:'06',
               Jul:'07',Aug:'08',Sep:'09',Oct:'10',Nov:'11',Dec:'12'};

    // What kind of session a recording is, read out of the lesson name -
    // Echo360 records it there and nowhere else ("... - Lecture",
    // "CITS2211 Tutorial"). Leftmost keyword wins, so "Lecture 3 - lab demo"
    // stays a lecture. Word boundaries matter: a bare "lab" must not match
    // inside "collaborative".
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
    if (!m) throw new Error('not on a section page');
    var sectionId = m[1];

    var r = await fetch('/section/' + sectionId + '/syllabus', {credentials: 'include'});
    if (!r.ok) throw new Error('syllabus HTTP ' + r.status);
    var json = await r.json();

    var lessons = (json.data || []).filter(function (it) {
      return it.type === 'SyllabusLessonType' && it.lesson && it.lesson.hasContent;
    });
    if (!lessons.length) throw new Error('no lessons with content');

    // Course code, e.g. "ELEC1303", from the first lesson name. Derived, never
    // hardcoded.
    var prefix = ((lessons[0].lesson.lesson.name || '').match(/^([A-Z0-9]+)/) ||
                  ['', 'lesson'])[1];

    // Institution id, stamped into content URLs as "0000.<id>". Only needed as
    // a fallback when the syllabus does not already carry a full audio URL.
    var whole = JSON.stringify(json);
    var inst = (whole.match(/0000\.([0-9a-f-]{36})/) ||
                whole.match(/"institutionId"\s*:\s*"([0-9a-f-]{36})"/) || [])[1];

    var rows = [];
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

        var found = (JSON.stringify(medias[j])
          .match(/https:\/\/content\.echo360\.[^"'\\]*?\/audio\.mp3/) || [])[0];
        var url = found ||
          (inst ? 'https://content.echo360.net.au/0000.' + inst + '/' +
                  medias[j].id + '/1/audio.mp3'
                : null);

        if (url) rows.push(filename + '\t' + url);
      }
    }

    window.__echo = {status: 'done', prefix: prefix, count: rows.length, rows: rows};
  } catch (e) {
    window.__echo = {status: 'error', error: String(e)};
  }
})();

'started';
