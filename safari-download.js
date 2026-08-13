// safari-download.js
//
// Runs inside the Echo360 section page in Safari, after safari-manifest.js has
// left the lecture list on window.__echo.
//
// Downloads the audio from the page itself. This works because the request
// carries Safari's existing session automatically - the CloudFront cookies are
// HttpOnly, so no script can read them, but the browser still sends them - and
// because content.echo360.net.au serves the audio CORS-readable, so the bytes
// can be read back and handed to the browser as a download.
//
// That is why nothing here needs cookies, a second browser, or a login.
//
// get-lectures.sh prepends "window.__skip = [...]" with the files that already
// have a transcript, so nothing gets fetched twice.

window.__dl = {status: 'running', done: [], failed: [], skipped: 0, current: null};

(async function () {
  try {
    if (!window.__echo || window.__echo.status !== 'done') {
      throw new Error('no manifest on the page - did it reload?');
    }
    var skip = window.__skip || [];
    var rows = window.__echo.rows;

    for (var i = 0; i < rows.length; i++) {
      var name = rows[i].split('\t')[0];
      var url  = rows[i].split('\t')[1];

      if (skip.indexOf(name) !== -1) { window.__dl.skipped++; continue; }

      window.__dl.current = name + ' (' + (i + 1) + '/' + rows.length + ')';
      try {
        var r = await fetch(url, {credentials: 'include'});
        if (!r.ok) throw new Error('HTTP ' + r.status);
        var blob = await r.blob();

        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = name;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);

        // Give Safari a moment to take the blob before releasing it.
        await new Promise(function (res) { setTimeout(res, 1500); });
        URL.revokeObjectURL(a.href);

        window.__dl.done.push(name + '\t' + blob.size);
      } catch (e) {
        window.__dl.failed.push(name + '\t' + String(e));
      }
      window.__dl.current = null;
    }

    window.__dl.status = 'done';
  } catch (e) {
    window.__dl = {status: 'error', error: String(e),
                   done: window.__dl.done, failed: window.__dl.failed};
  }
})();

'started';
