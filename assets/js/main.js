'use strict';

// Copy-to-clipboard for install command blocks
document.querySelectorAll('.cmd-block__copy').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var text = btn.closest('.cmd-block').querySelector('.cmd-block__text').textContent.trim();
    if (!navigator.clipboard) {
      fallbackCopy(text, btn);
      return;
    }
    navigator.clipboard.writeText(text).then(function() {
      showCopied(btn);
    }).catch(function() {
      fallbackCopy(text, btn);
    });
  });
});

function fallbackCopy(text, btn) {
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); showCopied(btn); } catch(e) {}
  document.body.removeChild(ta);
}

function showCopied(btn) {
  var orig = btn.textContent;
  btn.textContent = 'Copied!';
  btn.classList.add('copied');
  setTimeout(function() {
    btn.textContent = orig;
    btn.classList.remove('copied');
  }, 2000);
}
