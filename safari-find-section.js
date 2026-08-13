// safari-find-section.js
//
// Runs on the Echo360 courses page. get-lectures.sh prepends
// "window.__unit = '<CODE>'" before this file.
//
// The course grid renders lazily, so most units are not in the DOM until they
// are searched for - which is why this drives the page's own search box rather
// than scraping whatever happens to be on screen. Each course card is an anchor
// carrying both the section URL and an aria-label of the form:
//
//   "2026 - CITS1402 - CITS1402_SEM-1_2026 - Relational Database Management Systems"
//
// so the unit code can be matched exactly rather than by substring.

window.__find = {status: 'running'};

(function () {
  try {
    var unit = window.__unit;
    if (!unit) throw new Error('no unit code given');

    var inputs = document.querySelectorAll('input');
    var box = null;
    for (var i = 0; i < inputs.length; i++) {
      var hint = ((inputs[i].placeholder || '') + ' ' +
                  (inputs[i].getAttribute('aria-label') || '')).toLowerCase();
      if (hint.indexOf('search') !== -1) { box = inputs[i]; break; }
    }
    if (!box) throw new Error('could not find the course search box');

    // React tracks the input's value internally, so setting .value directly is
    // ignored. Go through the native setter and fire the event React listens for.
    var setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value').set;
    setter.call(box, unit);
    box.dispatchEvent(new Event('input', {bubbles: true}));

    // The grid re-renders asynchronously; poll for it to settle.
    var tries = 0;
    var timer = setInterval(function () {
      tries++;
      var links = document.querySelectorAll("a[href*='/section/']");
      var hits = [];
      var re = new RegExp('(^|[^A-Z0-9])' + unit + '([^A-Z0-9]|$)', 'i');

      for (var j = 0; j < links.length; j++) {
        var label = links[j].getAttribute('aria-label') || '';
        if (re.test(label)) {
          hits.push({label: label, href: links[j].getAttribute('href')});
        }
      }

      if (hits.length) {
        clearInterval(timer);
        // Labels start with the year, so the newest offering sorts first.
        hits.sort(function (a, b) { return a.label < b.label ? 1 : -1; });
        window.__find = {status: 'done', href: hits[0].href,
                         label: hits[0].label, matches: hits.length};
      } else if (/Nothing matched/i.test(document.body.innerText)) {
        clearInterval(timer);
        window.__find = {status: 'notfound'};
      } else if (tries > 20) {
        clearInterval(timer);
        window.__find = {status: 'timeout'};
      }
    }, 500);
  } catch (e) {
    window.__find = {status: 'error', error: String(e)};
  }
})();

'started';
