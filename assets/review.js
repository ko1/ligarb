// ligarb serve — review/comment system (SSE-driven)
(function() {
  'use strict';

  var API = '/_ligarb';
  var panel = null;
  var listPanel = null;
  var currentReviewId = null;

  // ── Utility ──

  function fetchJSON(url, opts) {
    opts = opts || {};
    opts.headers = opts.headers || {};
    if (opts.body && typeof opts.body === 'object') {
      opts.body = JSON.stringify(opts.body);
      opts.headers['Content-Type'] = 'application/json';
    }
    return fetch(url, opts).then(function(r) { return r.json(); });
  }

  function escapeHTML(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function formatTime(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    return d.toLocaleString();
  }

  // ── SSE: listen for review updates ──

  function waitForSSE() {
    if (window._ligarbEvents) {
      window._ligarbEvents.addEventListener('review_updated', function(e) {
        var data = JSON.parse(e.data);
        // Update open panel if it matches
        if (currentReviewId && data.id === currentReviewId) {
          loadReview(currentReviewId);
        }
        // Update badge
        updateBadge();
      });
    } else {
      setTimeout(waitForSSE, 100);
    }
  }
  waitForSSE();

  // ── Comment Button on Text Selection ──

  var commentBtn = document.createElement('button');
  commentBtn.id = 'ligarb-comment-btn';
  commentBtn.textContent = 'Comment';
  commentBtn.style.display = 'none';
  document.body.appendChild(commentBtn);

  var selectionData = null;

  document.addEventListener('mouseup', function(e) {
    if (e.target.closest('#ligarb-panel, #ligarb-list-panel, #ligarb-comment-btn')) return;

    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      commentBtn.style.display = 'none';
      selectionData = null;
      return;
    }

    var anchor = sel.anchorNode;
    var chapter = anchor ? anchor.parentElement.closest('.chapter') : null;
    if (!chapter) {
      commentBtn.style.display = 'none';
      selectionData = null;
      return;
    }

    var chapterSlug = chapter.id.replace('chapter-', '');
    var selectedText = sel.toString().trim();

    // Find nearest heading before selection
    var headingId = '';
    var headings = chapter.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');
    var range = sel.getRangeAt(0);
    for (var i = headings.length - 1; i >= 0; i--) {
      var headingRange = document.createRange();
      headingRange.selectNode(headings[i]);
      if (range.compareBoundaryPoints(Range.START_TO_START, headingRange) >= 0) {
        headingId = headings[i].id;
        break;
      }
    }

    selectionData = {
      chapter_slug: chapterSlug,
      heading_id: headingId,
      selected_text: selectedText.substring(0, 500)
    };

    var rect = sel.getRangeAt(0).getBoundingClientRect();
    commentBtn.style.display = 'block';
    commentBtn.style.top = (window.scrollY + rect.bottom + 5) + 'px';
    commentBtn.style.left = (window.scrollX + rect.left) + 'px';
  });

  commentBtn.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    if (!selectionData) return;
    commentBtn.style.display = 'none';
    openNewCommentPanel(selectionData);
    selectionData = null;
    window.getSelection().removeAllRanges();
  });

  // ── Review Panel ──

  function createPanel() {
    if (panel) return;
    panel = document.createElement('div');
    panel.id = 'ligarb-panel';
    panel.innerHTML =
      '<div class="ligarb-panel-header">' +
        '<span class="ligarb-panel-title">Review</span>' +
        '<button class="ligarb-panel-close">&times;</button>' +
      '</div>' +
      '<div class="ligarb-panel-body">' +
        '<div class="ligarb-context"></div>' +
        '<div class="ligarb-messages"></div>' +
        '<div class="ligarb-input-area">' +
          '<textarea class="ligarb-input" placeholder="Type a message..." rows="3"></textarea>' +
          '<div class="ligarb-actions">' +
            '<button class="ligarb-btn ligarb-btn-send">Send</button>' +
            '<button class="ligarb-btn ligarb-btn-approve">Approve</button>' +
            '<button class="ligarb-btn ligarb-btn-close-thread">Dismiss</button>' +
          '</div>' +
        '</div>' +
      '</div>';
    document.body.appendChild(panel);

    panel.querySelector('.ligarb-panel-close').addEventListener('click', closePanel);
    panel.querySelector('.ligarb-btn-send').addEventListener('click', sendMessage);
    panel.querySelector('.ligarb-btn-approve').addEventListener('click', approveReview);
    panel.querySelector('.ligarb-btn-close-thread').addEventListener('click', closeThread);

    panel.querySelector('.ligarb-input').addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        sendMessage();
      }
    });
  }

  function closePanel() {
    if (panel) {
      panel.classList.remove('open');
      currentReviewId = null;
    }
  }

  function openNewCommentPanel(context) {
    createPanel();
    currentReviewId = null;

    panel.querySelector('.ligarb-panel-title').textContent = 'New Comment';
    panel.querySelector('.ligarb-context').innerHTML =
      '<div class="ligarb-selected-text">"' + escapeHTML(context.selected_text) + '"</div>';
    panel.querySelector('.ligarb-messages').innerHTML = '';
    panel.querySelector('.ligarb-input').value = '';
    panel.querySelector('.ligarb-input').placeholder = 'Write your comment...';
    panel.querySelector('.ligarb-input').disabled = false;
    panel.querySelector('.ligarb-btn-send').disabled = false;
    panel.querySelector('.ligarb-btn-approve').style.display = 'none';
    panel.querySelector('.ligarb-btn-close-thread').style.display = 'none';
    panel.querySelector('.ligarb-btn-send').textContent = 'Comment';

    panel._createContext = context;

    panel.classList.add('open');
    panel.addEventListener('transitionend', function onEnd() {
      panel.removeEventListener('transitionend', onEnd);
      panel.querySelector('.ligarb-input').focus();
    });
  }

  function openReviewPanel(reviewId) {
    createPanel();
    currentReviewId = reviewId;
    panel._createContext = null;

    panel.querySelector('.ligarb-panel-title').textContent = 'Review';
    panel.querySelector('.ligarb-messages').innerHTML = '<div class="ligarb-loading">Loading...</div>';
    panel.querySelector('.ligarb-input').value = '';
    panel.querySelector('.ligarb-btn-send').textContent = 'Reply';
    panel.querySelector('.ligarb-btn-approve').style.display = '';
    panel.querySelector('.ligarb-btn-close-thread').style.display = '';

    panel.classList.add('open');
    loadReview(reviewId);
  }

  function loadReview(id) {
    fetchJSON(API + '/reviews/' + id).then(function(review) {
      if (currentReviewId !== id) return;
      renderReview(review);
    });
  }

  function renderReview(review) {
    var ctx = review.context || {};
    panel.querySelector('.ligarb-context').innerHTML =
      '<div class="ligarb-selected-text">"' + escapeHTML(ctx.selected_text || '') + '"</div>' +
      '<div class="ligarb-meta">Chapter: ' + escapeHTML(ctx.chapter_slug || '') + '</div>';

    var msgsEl = panel.querySelector('.ligarb-messages');
    msgsEl.innerHTML = '';

    (review.messages || []).forEach(function(msg) {
      var div = document.createElement('div');
      div.className = 'ligarb-message ligarb-message-' + msg.role;
      div.innerHTML =
        '<div class="ligarb-message-role">' + (msg.role === 'user' ? 'You' : 'Claude') + '</div>' +
        '<div class="ligarb-message-content">' + formatMessageContent(msg.content) + '</div>' +
        '<div class="ligarb-message-time">' + formatTime(msg.timestamp) + '</div>';
      msgsEl.appendChild(div);
    });

    // Show processing indicator when waiting for Claude
    var lastMsg = review.messages && review.messages[review.messages.length - 1];
    var isApplying = review.status === 'applying';
    var waitingForClaude = lastMsg && lastMsg.role === 'user' && review.status === 'open';

    if (isApplying) {
      msgsEl.appendChild(makeThinkingBubble('Applying changes...'));
    } else if (waitingForClaude) {
      msgsEl.appendChild(makeThinkingBubble('Claude is thinking...'));
    }

    msgsEl.scrollTop = msgsEl.scrollHeight;

    var isOpen = review.status === 'open';
    panel.querySelector('.ligarb-input').disabled = !isOpen;
    panel.querySelector('.ligarb-btn-send').disabled = !isOpen;
    panel.querySelector('.ligarb-btn-approve').disabled = !isOpen;
    panel.querySelector('.ligarb-btn-close-thread').disabled = isApplying;

    if (review.status === 'applied') {
      panel.querySelector('.ligarb-panel-title').textContent = 'Review (Applied)';
    } else if (review.status === 'closed') {
      panel.querySelector('.ligarb-panel-title').textContent = 'Review (Closed)';
    } else if (isApplying) {
      panel.querySelector('.ligarb-panel-title').textContent = 'Review (Applying...)';
    } else {
      panel.querySelector('.ligarb-panel-title').textContent = 'Review';
    }
  }

  function formatMessageContent(content) {
    if (!content) return '';

    // Split on <patch> blocks
    var parts = content.split(/(<patch>[\s\S]*?<\/patch>)/g);
    var hasPatch = false;
    var html = '';
    var patches = '';

    parts.forEach(function(part) {
      var m = part.match(/<patch>\s*<<<\n([\s\S]*?)\n===\n([\s\S]*?)\n>>>\s*<\/patch>/);
      if (m) {
        hasPatch = true;
        patches +=
          '<div class="ligarb-patch">' +
            '<div class="ligarb-patch-del">' + escapeHTML(m[1]) + '</div>' +
            '<div class="ligarb-patch-add">' + escapeHTML(m[2]) + '</div>' +
          '</div>';
      } else {
        html += escapeHTML(part)
          .replace(/\n/g, '<br>')
          .replace(/`([^`]+)`/g, '<code>$1</code>');
      }
    });

    if (hasPatch) {
      html += '<button class="ligarb-patch-toggle" onclick="this.nextElementSibling.classList.toggle(\'open\'); this.textContent = this.nextElementSibling.classList.contains(\'open\') ? \'Hide patch\' : \'Show patch\'">Show patch</button>';
      html += '<div class="ligarb-patch-container">' + patches + '</div>';
    }

    return html;
  }

  function makeThinkingBubble(text) {
    var div = document.createElement('div');
    div.className = 'ligarb-message ligarb-message-assistant ligarb-thinking';
    div.innerHTML =
      '<div class="ligarb-message-role">Claude</div>' +
      '<div class="ligarb-message-content"><span class="ligarb-dots"></span> ' + escapeHTML(text) + '</div>';
    return div;
  }

  function sendMessage() {
    var input = panel.querySelector('.ligarb-input');
    var message = input.value.trim();
    if (!message) return;

    input.value = '';

    if (panel._createContext) {
      var ctx = panel._createContext;
      panel._createContext = null;
      panel.querySelector('.ligarb-btn-send').textContent = 'Reply';

      fetchJSON(API + '/reviews', {
        method: 'POST',
        body: { context: ctx, message: message }
      }).then(function(review) {
        currentReviewId = review.id;
        panel.querySelector('.ligarb-btn-approve').style.display = '';
        panel.querySelector('.ligarb-btn-close-thread').style.display = '';
        renderReview(review);
        updateBadge();
      });
      return;
    }

    if (!currentReviewId) return;

    fetchJSON(API + '/reviews/' + currentReviewId + '/messages', {
      method: 'POST',
      body: { message: message }
    }).then(function(review) {
      renderReview(review);
    });
  }

  function approveReview() {
    if (!currentReviewId) return;
    if (!confirm('Apply the discussed changes to the source file?')) return;

    fetchJSON(API + '/reviews/' + currentReviewId + '/approve', {
      method: 'POST'
    }).then(function(review) {
      renderReview(review);
    });
  }

  function closeThread() {
    if (!currentReviewId) return;

    fetchJSON(API + '/reviews/' + currentReviewId, {
      method: 'DELETE'
    }).then(function(review) {
      renderReview(review);
      updateBadge();
    });
  }

  // ── Review List Panel ──

  var listBtn = document.createElement('button');
  listBtn.id = 'ligarb-list-btn';
  listBtn.innerHTML = '&#9993;';
  listBtn.title = 'Review threads';
  document.body.appendChild(listBtn);

  var badge = document.createElement('span');
  badge.id = 'ligarb-badge';
  badge.style.display = 'none';
  listBtn.appendChild(badge);

  listBtn.addEventListener('click', function() {
    toggleListPanel();
  });

  function toggleListPanel() {
    if (listPanel && listPanel.classList.contains('open')) {
      listPanel.classList.remove('open');
      return;
    }
    createListPanel();
    listPanel.classList.add('open');
    loadReviewList();
  }

  function createListPanel() {
    if (listPanel) return;
    listPanel = document.createElement('div');
    listPanel.id = 'ligarb-list-panel';
    listPanel.innerHTML =
      '<div class="ligarb-panel-header">' +
        '<span class="ligarb-panel-title">Reviews</span>' +
        '<button class="ligarb-panel-close">&times;</button>' +
      '</div>' +
      '<div class="ligarb-list-body"></div>';
    document.body.appendChild(listPanel);

    listPanel.querySelector('.ligarb-panel-close').addEventListener('click', function() {
      listPanel.classList.remove('open');
    });
  }

  function loadReviewList() {
    fetchJSON(API + '/reviews').then(function(reviews) {
      var body = listPanel.querySelector('.ligarb-list-body');
      if (!reviews || reviews.length === 0) {
        body.innerHTML = '<div class="ligarb-list-empty">No reviews yet.</div>';
        return;
      }

      body.innerHTML = '';
      reviews.forEach(function(r) {
        var item = document.createElement('div');
        item.className = 'ligarb-list-item ligarb-list-' + r.status;
        var statusIcon = r.status === 'open' ? '&#9679;' : r.status === 'applied' ? '&#10003;' : '&#10005;';
        item.innerHTML =
          '<div class="ligarb-list-item-header">' +
            '<span class="ligarb-list-status">' + statusIcon + '</span>' +
            '<span class="ligarb-list-text">"' + escapeHTML((r.context && r.context.selected_text || '').substring(0, 60)) + '"</span>' +
          '</div>' +
          '<div class="ligarb-list-item-meta">' +
            escapeHTML(r.context && r.context.chapter_slug || '') +
            ' &middot; ' + r.message_count + ' messages' +
            ' &middot; ' + formatTime(r.created_at) +
          '</div>';
        item.addEventListener('click', function() {
          listPanel.classList.remove('open');
          openReviewPanel(r.id);
        });
        body.appendChild(item);
      });
    });
  }

  function updateBadge() {
    fetchJSON(API + '/reviews').then(function(reviews) {
      var open = (reviews || []).filter(function(r) { return r.status === 'open' || r.status === 'applying'; }).length;
      if (open > 0) {
        badge.textContent = open;
        badge.style.display = 'inline-block';
        listBtn.classList.add('has-open');
      } else {
        badge.style.display = 'none';
        listBtn.classList.remove('has-open');
      }
    });
  }

  // Initial badge
  updateBadge();
})();
