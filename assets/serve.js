// ligarb serve — reload button + mtime polling + auto content refresh
(function() {
  'use strict';

  var lastMtime = 0;
  var pollInterval = 2000;
  var refreshing = false;

  // Create reload button
  var reloadBtn = document.createElement('button');
  reloadBtn.id = 'ligarb-reload';
  reloadBtn.innerHTML = '&#8635;';
  reloadBtn.title = 'Reload page';
  reloadBtn.addEventListener('click', function() {
    refreshContent();
  });
  document.body.appendChild(reloadBtn);

  // Refresh only the book content (main area), preserving panel state
  function refreshContent() {
    if (refreshing) return;
    refreshing = true;
    reloadBtn.classList.remove('has-update');
    reloadBtn.classList.add('refreshing');

    fetch('/?_t=' + Date.now())
      .then(function(r) { return r.text(); })
      .then(function(html) {
        var parser = new DOMParser();
        var doc = parser.parseFromString(html, 'text/html');
        var newMain = doc.getElementById('content');
        var oldMain = document.getElementById('content');
        if (newMain && oldMain) {
          oldMain.innerHTML = newMain.innerHTML;
          // Re-show current chapter via the book's exposed function
          var hash = location.hash.replace('#', '');
          if (hash && window.showChapter) {
            // If it's a deep link (chapter--heading), show the chapter part
            var slug = hash.split('--')[0];
            window.showChapter(slug);
          }
        }
        refreshing = false;
        reloadBtn.classList.remove('refreshing');
      })
      .catch(function() {
        // Fallback to full reload if content swap fails
        refreshing = false;
        reloadBtn.classList.remove('refreshing');
        location.reload();
      });
  }

  // Expose for review.js to trigger
  window._ligarbRefreshContent = refreshContent;

  // Poll for mtime changes
  function pollStatus() {
    fetch('/_ligarb/status')
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (lastMtime === 0) {
          lastMtime = data.mtime;
          return;
        }
        if (data.mtime > lastMtime) {
          lastMtime = data.mtime;
          // Auto-refresh content without full page reload
          refreshContent();
        }
      })
      .catch(function() { /* server may be restarting */ });
  }

  pollStatus();
  setInterval(pollStatus, pollInterval);
})();
