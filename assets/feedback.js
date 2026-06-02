// ligarb public feedback UI — "Report as issue"
// Static and backend-free: on text selection it offers a button that builds a
// prefilled GitHub Issue form URL (from data-src-* + window.location + the
// configured repository) and opens it in a new tab. No API calls, no tokens.
(function() {
  'use strict';

  var cfg = window._ligarbReview;
  if (!cfg || !cfg.base) return;

  var ISSUE_BASE = cfg.base.replace(/\/+$/, '') + '/issues/new';
  var TEMPLATE = cfg.issueTemplate || 'book-feedback.yml';
  var LABELS = Array.isArray(cfg.labels) ? cfg.labels : [];

  // Keep the whole URL comfortably under common limits (~8KB).
  var MAX_QUOTE = 1200;
  var MAX_URL = 7000;

  // Short label -> value stored in the issue (the form keeps its own dropdown;
  // we fold the reader's choice into `details` since dropdown prefill is flaky).
  var TYPES = [
    { value: '', label: '種類を選択 / Type…' },
    { value: '誤り (error)', label: '誤り / Error' },
    { value: 'わかりにくい (unclear)', label: 'わかりにくい / Unclear' },
    { value: '疑問 (question)', label: '疑問 / Question' }
  ];

  function enc(s) { return encodeURIComponent(s == null ? '' : s); }

  function escapeHTML(str) {
    var div = document.createElement('div');
    div.textContent = str == null ? '' : str;
    return div.innerHTML;
  }

  // ── Selection capture (mirrors the serve review UI) ──

  var btn = document.createElement('button');
  btn.id = 'ligarb-fb-btn';
  btn.type = 'button';
  btn.textContent = 'Report as issue';
  document.body.appendChild(btn);

  var current = null; // { quote, chapterTitle, srcFile, headingText }

  document.addEventListener('mouseup', function(e) {
    if (e.target.closest('#ligarb-fb-btn, #ligarb-fb-panel')) return;

    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      hideButton();
      return;
    }

    var anchor = sel.anchorNode;
    var chapter = anchor && anchor.parentElement ? anchor.parentElement.closest('.chapter') : null;
    if (!chapter || !chapter.dataset.srcFile) {
      hideButton();
      return;
    }

    current = {
      quote: sel.toString().trim(),
      chapterTitle: chapter.dataset.srcTitle || '',
      srcFile: chapter.dataset.srcFile || '',
      headingText: nearestHeadingText(chapter, sel)
    };

    var rect = sel.getRangeAt(0).getBoundingClientRect();
    btn.style.display = 'block';
    btn.style.top = (window.scrollY + rect.bottom + 6) + 'px';
    btn.style.left = (window.scrollX + rect.left) + 'px';
  });

  function hideButton() {
    btn.style.display = 'none';
    current = null;
  }

  function nearestHeadingText(chapter, sel) {
    var headings = chapter.querySelectorAll('h1[id], h2[id], h3[id]');
    if (!headings.length) return '';
    var range = sel.getRangeAt(0);
    for (var i = headings.length - 1; i >= 0; i--) {
      var hr = document.createRange();
      hr.selectNode(headings[i]);
      if (range.compareBoundaryPoints(Range.START_TO_START, hr) >= 0) {
        return headings[i].textContent.trim();
      }
    }
    return headings[0].textContent.trim();
  }

  btn.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    if (!current) return;
    openPanel(current);
    hideButton();
  });

  // ── Report panel ──

  var panel = null;

  function buildPanel() {
    if (panel) return;
    panel = document.createElement('div');
    panel.id = 'ligarb-fb-panel';
    var options = TYPES.map(function(t) {
      return '<option value="' + escapeHTML(t.value) + '">' + escapeHTML(t.label) + '</option>';
    }).join('');
    panel.innerHTML =
      '<div class="ligarb-fb-title">Report as issue</div>' +
      '<div class="ligarb-fb-quote"></div>' +
      '<label class="ligarb-fb-label" for="ligarb-fb-type">種類 / Type</label>' +
      '<select id="ligarb-fb-type">' + options + '</select>' +
      '<label class="ligarb-fb-label" for="ligarb-fb-details">コメント / Comment</label>' +
      '<textarea id="ligarb-fb-details" placeholder="何が問題か、どう直すとよいか…"></textarea>' +
      '<div class="ligarb-fb-actions">' +
        '<button type="button" class="ligarb-fb-cancel">Cancel</button>' +
        '<button type="button" class="ligarb-fb-submit">Report as issue</button>' +
      '</div>';
    document.body.appendChild(panel);

    panel.querySelector('.ligarb-fb-cancel').addEventListener('click', closePanel);
    panel.querySelector('.ligarb-fb-submit').addEventListener('click', submit);
  }

  function openPanel(ctx) {
    buildPanel();
    panel._ctx = ctx;
    panel.querySelector('.ligarb-fb-quote').textContent = ctx.quote;
    panel.querySelector('#ligarb-fb-type').value = '';
    panel.querySelector('#ligarb-fb-details').value = '';

    // Center-ish, then clamp into the viewport.
    panel.classList.add('open');
    var w = panel.offsetWidth, h = panel.offsetHeight;
    var top = Math.max(12, (window.innerHeight - h) / 2);
    var left = Math.max(12, (window.innerWidth - w) / 2);
    panel.style.top = top + 'px';
    panel.style.left = left + 'px';
    panel.querySelector('#ligarb-fb-details').focus();
  }

  function closePanel() {
    if (panel) panel.classList.remove('open');
  }

  function submit() {
    var ctx = panel._ctx;
    if (!ctx) return;
    var type = panel.querySelector('#ligarb-fb-type').value;
    var comment = panel.querySelector('#ligarb-fb-details').value.trim();

    var locationLines = [];
    var section = [ctx.chapterTitle, ctx.headingText].filter(Boolean).join(' › ');
    if (section) locationLines.push('章/節: ' + section);
    if (ctx.srcFile) locationLines.push('ソース: ' + ctx.srcFile);
    locationLines.push('URL: ' + window.location.href);

    var detailsLines = [];
    if (type) detailsLines.push('種類: ' + type);
    if (comment) detailsLines.push(comment);

    var quote = ctx.quote;
    if (quote.length > MAX_QUOTE) quote = quote.slice(0, MAX_QUOTE) + ' …(truncated)';

    var url = buildUrl(locationLines.join('\n'), quote, detailsLines.join('\n\n'));

    // If still too long, progressively shorten the quote.
    while (url.length > MAX_URL && quote.length > 80) {
      quote = quote.slice(0, Math.floor(quote.length / 2)) + ' …(truncated)';
      url = buildUrl(locationLines.join('\n'), quote, detailsLines.join('\n\n'));
    }

    window.open(url, '_blank', 'noopener');
    closePanel();
  }

  function buildUrl(location, quote, details) {
    var params = 'template=' + enc(TEMPLATE);
    if (LABELS.length) params += '&labels=' + enc(LABELS.join(','));
    params += '&location=' + enc(location);
    params += '&quote=' + enc(quote);
    params += '&details=' + enc(details);
    return ISSUE_BASE + '?' + params;
  }

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closePanel();
  });
})();
