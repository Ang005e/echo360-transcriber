

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

    var setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value').set;
    setter.call(box, unit);
    box.dispatchEvent(new Event('input', {bubbles: true}));

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
