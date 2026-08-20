

window.__login = {status: 'running'};

(function () {
  try {
    var email = window.__email;
    if (!email) throw new Error('no email given');

    function visible(el) {
      return el.offsetWidth > 0 || el.offsetHeight > 0;
    }

    var inputs = document.querySelectorAll('input');
    var box = null;

    for (var i = 0; i < inputs.length && !box; i++) {
      if (inputs[i].type === 'email' && visible(inputs[i])) box = inputs[i];
    }
    for (var j = 0; j < inputs.length && !box; j++) {
      var hint = ((inputs[j].name || '') + ' ' +
                  (inputs[j].id || '') + ' ' +
                  (inputs[j].placeholder || '') + ' ' +
                  (inputs[j].getAttribute('aria-label') || '')).toLowerCase();
      if (/email|user|login/.test(hint) && visible(inputs[j])) box = inputs[j];
    }
    for (var k = 0; k < inputs.length && !box; k++) {
      if (inputs[k].type === 'text' && visible(inputs[k])) box = inputs[k];
    }
    if (!box) throw new Error('no email field on this page');

    var setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value').set;
    setter.call(box, email);
    box.dispatchEvent(new Event('input', {bubbles: true}));
    box.dispatchEvent(new Event('change', {bubbles: true}));

    var form = box.form;
    var btn = document.querySelector('button[type=submit], input[type=submit]');
    if (!btn) {
      var buttons = document.querySelectorAll('button');
      for (var b = 0; b < buttons.length && !btn; b++) {
        if (visible(buttons[b]) && !buttons[b].disabled) btn = buttons[b];
      }
    }

    if (btn) {
      btn.click();
    } else if (form) {
      form.submit();
    } else {
      throw new Error('no submit button on this page');
    }

    window.__login = {status: 'submitted', field: box.name || box.id || box.type};
  } catch (e) {
    window.__login = {status: 'error', error: String(e)};
  }
})();

'started';
