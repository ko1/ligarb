// ligarb serve — review/comment system
(function() {
  'use strict';

  var API = '/_ligarb';
  var panel = null;
  var listPanel = null;
  var currentReviewId = null;
  var pollTimer = null;

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

  // ── Comment Button on Text Selection ──

  var commentBtn = document.createElement('button');
  commentBtn.id = 'ligarb-comment-btn';
  commentBtn.textContent = 'Comment';
  commentBtn.style.display = 'none';
  document.body.appendChild(commentBtn);

  var selectionData = null;

  document.addEventListener('mouseup', function(e) {
    // Ignore clicks inside our UI
    if (e.target.closest('#ligarb-panel, #ligarb-list-panel, #ligarb-comment-btn')) return;

    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      commentBtn.style.display = 'none';
      selectionData = null;
      return;
    }

    // Only for content inside .chapter sections
    var anchor = sel.anchorNode;
    var chapter = anchor ? anchor.parentElement.closest('.chapter') : null;
    if (!chapter) {
      commentBtn.style.display = 'none';
      selectionData = null;
      return;
    }

    var chapterSlug = chapter.id.replace('chapter-', '');
    var selectedText = sel.toString().trim();

    // Find nearest heading
    var headingId = '';
    var node = sel.anchorNode.nodeType === 3 ? sel.anchorNode.parentElement : sel.anchorNode;
    while (node && node !== chapter) {
      if (node.previousElementSibling) {
        var prev = node.previousElementSibling;
        if (/^H[1-6]$/.test(prev.tagName) && prev.id) {
          headingId = prev.id;
          break;
        }
      }
      // Check the node itself
      if (/^H[1-6]$/.test(node.tagName) && node.id) {
        headingId = node.id;
        break;
      }
      node = node.parentElement;
    }
    if (!headingId) {
      // Find last heading before selection
      var headings = chapter.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');
      var range = sel.getRangeAt(0);
      for (var i = headings.length - 1; i >= 0; i--) {
        if (range.compareBoundaryPoints(Range.START_TO_START,
            document.createRange().selectNode ? (function() { var r = document.createRange(); r.selectNode(headings[i]); return r; })() : range) >= 0) {
          headingId = headings[i].id;
          break;
        }
      }
    }

    selectionData = {
      chapter_slug: chapterSlug,
      heading_id: headingId,
      selected_text: selectedText.substring(0, 500)
    };

    // Position button near the selection
    var rect = sel.getRangeAt(0).getBoundingClientRect();
    commentBtn.style.display = 'block';
    commentBtn.style.top = (window.scrollY + rect.bottom + 5) + 'px';
    commentBtn.style.left = (window.scrollX + rect.left) + 'px';
  });

  // Hide comment button on scroll or click elsewhere
  document.addEventListener('mousedown', function(e) {
    if (e.target === commentBtn) return;
    if (e.target.closest('#ligarb-panel, #ligarb-list-panel')) return;
    // Don't hide immediately — mouseup handler will decide
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
            '<button class="ligarb-btn ligarb-btn-close-thread">Close</button>' +
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
      stopPolling();
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
    panel.querySelector('.ligarb-btn-approve').style.display = 'none';
    panel.querySelector('.ligarb-btn-close-thread').style.display = 'none';
    panel.querySelector('.ligarb-btn-send').textContent = 'Comment';

    // Override send to create new review
    panel._createContext = context;

    panel.classList.add('open');
    panel.querySelector('.ligarb-input').focus();
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
    startPolling(reviewId);
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

    msgsEl.scrollTop = msgsEl.scrollHeight;

    // Update UI based on status
    var isOpen = review.status === 'open';
    var isApplying = review.status === 'applying';
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
    }
  }

  function formatMessageContent(content) {
    if (!content) return '';
    // Simple markdown-like formatting
    return escapeHTML(content)
      .replace(/\n/g, '<br>')
      .replace(/`([^`]+)`/g, '<code>$1</code>');
  }

  function sendMessage() {
    var input = panel.querySelector('.ligarb-input');
    var message = input.value.trim();
    if (!message) return;

    input.value = '';

    // New review creation
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
        startPolling(review.id);
        updateBadge();
      });
      return;
    }

    // Reply to existing review
    if (!currentReviewId) return;

    var id = currentReviewId;
    stopPolling();

    fetchJSON(API + '/reviews/' + id + '/messages', {
      method: 'POST',
      body: { message: message }
    }).then(function(review) {
      renderReview(review);
      startPolling(id);
    });
  }

  function approveReview() {
    if (!currentReviewId) return;
    if (!confirm('Apply the discussed changes to the source file?')) return;

    var id = currentReviewId;
    // Stop polling to avoid interference with the approve request
    stopPolling();

    fetchJSON(API + '/reviews/' + id + '/approve', {
      method: 'POST'
    }).then(function(review) {
      renderReview(review);
      // Resume polling to watch for completion
      startPolling(id);
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

  // ── Polling for review updates ──

  function startPolling(reviewId) {
    stopPolling();
    pollTimer = setInterval(function() {
      if (currentReviewId !== reviewId) {
        stopPolling();
        return;
      }
      loadReview(reviewId);
    }, 2000);
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
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
      var open = (reviews || []).filter(function(r) { return r.status === 'open'; }).length;
      if (open > 0) {
        badge.textContent = open;
        badge.style.display = 'inline-block';
      } else {
        badge.style.display = 'none';
      }
    });
  }

  // Initial badge update
  updateBadge();
  setInterval(updateBadge, 10000);
})();
