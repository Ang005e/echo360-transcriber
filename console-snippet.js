

(async function () {
  var mon = {Jan:'01',Feb:'02',Mar:'03',Apr:'04',May:'05',Jun:'06',
             Jul:'07',Aug:'08',Sep:'09',Oct:'10',Nov:'11',Dec:'12'};

  var KIND_RE = /\b(lectures?|tutorials?|tuts?|workshops?|seminars?|practicals?|pracs?|labs?|revisions?)\b/i;
  var KIND_ALIAS = {tut: 'tutorial', prac: 'practical'};
  function kindOf(name) {
    var hit = name.match(KIND_RE);
    if (!hit) return 'lecture';
    var k = hit[1].toLowerCase().replace(/s$/, '');
    return KIND_ALIAS[k] || k;
  }

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

  var prefix = ((lessons[0].lesson.lesson.name || '').match(/^([A-Z0-9]+)/) || ['', 'lesson'])[1];

  var whole = JSON.stringify(json);
  var inst = (whole.match(/0000\.([0-9a-f-]{36})/) ||
              whole.match(/"institutionId"\s*:\s*"([0-9a-f-]{36})"/) ||
              [])[1];

  var lines = [];
  var seen = {};
  for (var i = 0; i < lessons.length; i++) {
    var name = lessons[i].lesson.lesson.name || '';
    var medias = lessons[i].lesson.medias || [];

    var date = dateOf(lessons[i], name, i);
    var kind = kindOf(name);

    for (var j = 0; j < medias.length; j++) {
      var sfx = medias.length > 1 ? '_' + (j + 1) : '';

      var base = prefix + '_' + date + '_' + kind + sfx;
      seen[base] = (seen[base] || 0) + 1;
      var filename = base + (seen[base] > 1 ? '_' + seen[base] : '') + '.mp3';

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
