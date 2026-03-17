// ligarb serve — SSE-based live reload + reload button
(function() {
  'use strict';

  var refreshing = false;

  // Create reload button (hidden by default, shown when build changes)
  var reloadBtn = document.createElement('button');
  reloadBtn.id = 'ligarb-reload';
  reloadBtn.innerHTML = '&#8635;';
  reloadBtn.title = 'New build available — click to reload';
  reloadBtn.style.display = 'none';
  reloadBtn.addEventListener('click', function() {
    refreshContent();
  });
  document.body.appendChild(reloadBtn);

  function showReloadButton() {
    reloadBtn.style.display = 'flex';
    reloadBtn.classList.add('has-update');
    reloadBtn.classList.remove('refreshing');
  }

  function hideReloadButton() {
    reloadBtn.style.display = 'none';
    reloadBtn.classList.remove('has-update', 'refreshing');
  }

  // Refresh book content without full page reload
  function refreshContent() {
    if (refreshing) return;
    refreshing = true;
    reloadBtn.classList.remove('has-update');
    reloadBtn.classList.add('refreshing');

    fetch((window._ligarbBase || '/') + '?_t=' + Date.now())
      .then(function(r) { return r.text(); })
      .then(function(html) {
        var parser = new DOMParser();
        var doc = parser.parseFromString(html, 'text/html');
        var newMain = doc.getElementById('content');
        var oldMain = document.getElementById('content');
        if (newMain && oldMain) {
          var scrollY = window.scrollY;
          oldMain.innerHTML = newMain.innerHTML;
          var hash = location.hash.replace('#', '');
          if (hash) {
            // Show the current chapter without scrolling to top
            var slug = hash.split('--')[0];
            var chapters = oldMain.querySelectorAll('.chapter');
            chapters.forEach(function(el) {
              el.style.display = el.id === 'chapter-' + slug ? 'block' : 'none';
            });
          }
          window.scrollTo(0, scrollY);
        }
        refreshing = false;
        hideReloadButton();
      })
      .catch(function() {
        refreshing = false;
        hideReloadButton();
        location.reload();
      });
  }

  // SSE connection
  var eventSource = new EventSource((window._ligarbAPI || '/_ligarb') + '/events');

  eventSource.addEventListener('build_updated', function() {
    showReloadButton();
  });

  // Expose for review.js
  window._ligarbEvents = eventSource;
})();
