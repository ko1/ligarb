# frozen_string_literal: true

require "webrick"
require "json"
require "base64"
require "securerandom"
require_relative "config"
require_relative "review_store"
require_relative "claude_runner"

module Ligarb
  class Server
    INJECTED_ASSETS = %w[serve.js review.js review.css].freeze

    BookEntry = Struct.new(:slug, :config, :config_path, :build_dir, :store, :claude, keyword_init: true)

    def initialize(config_paths, port: 3000, multi: false)
      @port = port
      @assets_dir = File.join(File.dirname(__FILE__), "..", "..", "assets")
      @sse_clients = [] # [[slug, queue], ...]
      @sse_mutex = Mutex.new
      @write_jobs = {} # slug => { title:, status:, error: }
      @write_mutex = Mutex.new

      @books = {}
      config_paths.each do |cp|
        config = Config.new(cp)
        slug = File.basename(config.base_dir)
        abort "Error: duplicate book slug '#{slug}' — use distinct directory names" if @books.key?(slug)
        @books[slug] = BookEntry.new(
          slug: slug,
          config: config,
          config_path: File.expand_path(cp),
          build_dir: config.output_path,
          store: ReviewStore.new(config.base_dir),
          claude: ClaudeRunner.new(config)
        )
      end

      @multi = multi || @books.size > 1

      @operation_queue = Queue.new
      @operation_thread = Thread.new { operation_worker }
      @operation_thread.abort_on_exception = true
    end

    def start
      require_relative "builder"
      @books.each_value do |book|
        puts "Building #{book.config.title}..."
        Builder.new(book.config_path).build
      end

      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: "127.0.0.1",
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO),
        AccessLog: [[File.open(File::NULL, "w"), WEBrick::AccessLog::COMMON_LOG_FORMAT]],
        RequestBodyMaxSize: 50 * 1024 * 1024
      )

      server.mount_proc("/_ligarb/") { |req, res| handle_api(req, res) }
      server.mount_proc("/") { |req, res| handle_static(req, res) }

      trap("INT") { Thread.new { close_sse_clients; server.shutdown } }
      trap("TERM") { Thread.new { close_sse_clients; server.shutdown } }

      @books.each_value { |book| start_build_watcher(book) }

      if @multi
        puts "Serving #{@books.size} books at http://localhost:#{@port}"
        @books.each_value { |b| puts "  /#{b.slug}/ — #{b.config.title}" }
      else
        book = @books.values.first
        puts "Serving #{book.config.title} at http://localhost:#{@port}"
        puts "  Build directory: #{book.build_dir}"
      end
      puts "  Press Ctrl+C to stop"

      server.start
    end

    private

    # ── Operation Queue ──

    def operation_worker
      loop do
        job = @operation_queue.pop
        job.call
      end
    end

    def enqueue_sync(&block)
      result_queue = Queue.new
      @operation_queue.push(-> {
        result_queue.push(block.call)
      })
      result_queue.pop
    end

    def enqueue_async(&block)
      @operation_queue.push(-> { block.call })
    end

    # ── SSE (Server-Sent Events) ──

    def close_sse_clients
      @sse_mutex.synchronize do
        @sse_clients.each { |_, q| q.push(:close) rescue nil }
        @sse_clients.clear
      end
    end

    def sse_broadcast(event, data, slug: nil)
      json = JSON.generate(data)
      message = "event: #{event}\ndata: #{json}\n\n"
      @sse_mutex.synchronize do
        @sse_clients.reject! do |client_slug, queue|
          next false if slug && client_slug != slug
          begin
            queue.push(message, true)
            false
          rescue ThreadError
            true # queue full, drop client
          end
        end
      end
    end

    def handle_sse(book_slug, _req, res)
      res["Content-Type"] = "text/event-stream"
      res["Cache-Control"] = "no-cache"
      res["Connection"] = "keep-alive"
      res["X-Accel-Buffering"] = "no"
      res.chunked = true

      queue = SizedQueue.new(50)
      @sse_mutex.synchronize { @sse_clients << [book_slug, queue] }

      res.body = proc { |socket|
        begin
          socket.write("retry: 3000\n\n")
          loop do
            msg = queue.pop
            break if msg == :close
            socket.write(msg)
          end
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError
          # Client disconnected
        ensure
          @sse_mutex.synchronize { @sse_clients.delete_if { |_, q| q == queue } }
        end
      }
    end

    # ── Build watcher ──

    def start_build_watcher(book)
      html_path = File.join(book.build_dir, "index.html")

      if use_inotify?
        log "Watching #{html_path} with inotify"
        Thread.new do
          Inotify.watch_file(html_path) do
            log "Build updated: #{book.slug} (inotify)"
            sse_broadcast("build_updated", { mtime: File.mtime(html_path).to_i }, slug: book.slug)
          end
        rescue => e
          log "inotify watcher error: #{e.message}, falling back to polling"
          start_mtime_poller(book)
        end
      else
        start_mtime_poller(book)
      end
    end

    def start_mtime_poller(book)
      html_path = File.join(book.build_dir, "index.html")
      log "Watching #{html_path} with polling"
      Thread.new do
        last_mtime = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
        loop do
          sleep 2
          current = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
          if current > last_mtime
            last_mtime = current
            sse_broadcast("build_updated", { mtime: current }, slug: book.slug)
          end
        rescue => e
          log "mtime watcher error: #{e.message}"
        end
      end
    end

    def use_inotify?
      return @use_inotify if defined?(@use_inotify)
      @use_inotify = begin
        require_relative "inotify"
        true
      rescue Fiddle::DLError, LoadError
        false
      end
    end

    # ── Static file serving ──

    def handle_static(req, res)
      path = req.path

      unless @multi
        # Single-book mode (original behavior)
        if path == "/" || path == "/index.html"
          serve_injected_html(@books.values.first, res)
          return
        end
        serve_static_file(@books.values.first.build_dir, path, res)
        return
      end

      # Multi-book mode
      if path == "/" || path == "/index.html"
        serve_index_page(res)
        return
      end

      # /<slug>/...
      if path =~ %r{^/([^/]+)(/.*)?$}
        book = @books[$1]
        if book
          sub_path = $2 || "/"
          if sub_path == "/" || sub_path == "/index.html"
            serve_injected_html(book, res)
            return
          end
          serve_static_file(book.build_dir, sub_path, res)
          return
        end
      end

      res.status = 404
      res.body = "Not Found"
    end

    def serve_static_file(build_dir, path, res)
      file_path = File.join(build_dir, path)
      file_path = File.realpath(file_path) rescue nil

      real_build_dir = File.realpath(build_dir)
      if file_path && (file_path.start_with?(real_build_dir + "/") || file_path == real_build_dir) && File.file?(file_path)
        res.body = File.binread(file_path)
        res["Content-Type"] = mime_type(file_path)
      else
        res.status = 404
        res.body = "Not Found"
      end
    end

    def serve_injected_html(book, res)
      html_path = File.join(book.build_dir, "index.html")
      html = File.read(html_path)

      css_tag = %(<link rel="stylesheet" href="/_ligarb/assets/review.css">)
      html.sub!("</head>", "#{css_tag}\n</head>")

      api_base = @multi ? "/_ligarb/#{book.slug}" : "/_ligarb"
      page_base = @multi ? "/#{book.slug}/" : "/"
      config_tag = %(<script>window._ligarbAPI='#{escape_js_string(api_base)}';window._ligarbBase='#{escape_js_string(page_base)}';</script>)

      js_tags = [config_tag] + %w[serve.js review.js].map { |f|
        %(<script src="/_ligarb/assets/#{f}"></script>)
      }
      html.sub!("</body>", "#{js_tags.join("\n")}\n</body>")

      res.body = html
      res["Content-Type"] = "text/html; charset=utf-8"
    end

    def serve_index_page(res)
      books_data = @books.values.sort_by { |b| b.config.title }.map { |book|
        html_path = File.join(book.build_dir, "index.html")
        mtime = File.exist?(html_path) ? File.mtime(html_path).strftime("%Y-%m-%d %H:%M") : nil
        {
          slug: book.slug,
          title: book.config.title,
          author: book.config.author.to_s,
          updated_at: mtime,
          toc: build_toc(book)
        }
      }
      books_json = JSON.generate(books_data)
      write_jobs_json = JSON.generate(write_jobs_data)

      html = <<~'HTML'
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>ligarb librarium</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: system-ui, -apple-system, sans-serif; color: #333; height: 100vh; display: flex; flex-direction: column; }
          .idx-header { padding: 14px 20px; border-bottom: 1px solid #e0e0e0; font-size: 20px; font-weight: 600; flex-shrink: 0; }
          .idx-container { display: flex; flex: 1; overflow: hidden; }
          .idx-books { width: 280px; border-right: 1px solid #e0e0e0; overflow-y: auto; padding: 8px; flex-shrink: 0; display: flex; flex-direction: column; }
          .idx-books-list { flex: 1; }
          .idx-book { padding: 12px 16px; border-radius: 6px; cursor: pointer; transition: background 0.15s; }
          .idx-book:hover { background: #f6f8fa; }
          .idx-book.active { background: #eff6ff; border-left: 3px solid #2563eb; padding-left: 13px; }
          .idx-book-title { font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
          .idx-book-author { font-size: 13px; color: #666; margin-top: 2px; }
          .idx-book-updated { font-size: 12px; color: #999; margin-top: 2px; }
          .idx-badge { font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 10px; white-space: nowrap; }
          .idx-badge-writing { background: #fff3e0; color: #e65100; animation: idx-pulse 1.5s ease-in-out infinite; }
          .idx-badge-done { background: #e8f5e9; color: #2e7d32; }
          .idx-badge-error { background: #ffebee; color: #c62828; }
          @keyframes idx-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
          .idx-write-btn { display: block; margin: 8px; padding: 10px; border: 2px dashed #ccc; border-radius: 6px; background: none; color: #666; font-size: 14px; cursor: pointer; transition: all 0.15s; text-align: center; flex-shrink: 0; }
          .idx-write-btn:hover { border-color: #2563eb; color: #2563eb; background: #f0f6ff; }
          .idx-toc { flex: 1; overflow-y: auto; padding: 20px 28px; }
          .idx-toc-empty { color: #999; font-size: 15px; padding: 60px 0; text-align: center; }
          .idx-toc-title { font-size: 18px; font-weight: 600; margin-bottom: 16px; }
          .idx-toc-title a { color: #2563eb; text-decoration: none; }
          .idx-toc-title a:hover { text-decoration: underline; }
          .idx-toc-part { font-size: 12px; font-weight: 700; color: #888; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 18px; margin-bottom: 6px; padding-left: 4px; }
          .idx-toc-ch { display: block; padding: 5px 12px; border-radius: 4px; text-decoration: none; color: #333; font-size: 14px; line-height: 1.5; transition: background 0.15s; }
          .idx-toc-ch:hover { background: #f6f8fa; }
          .idx-toc-cover { color: #666; font-style: italic; }
          .idx-form { max-width: 480px; }
          .idx-form h2 { font-size: 18px; margin-bottom: 16px; }
          .idx-form label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 4px; color: #555; }
          .idx-form input, .idx-form textarea { width: 100%; padding: 8px 10px; border: 1px solid #d0d0d0; border-radius: 4px; font-size: 14px; font-family: inherit; margin-bottom: 12px; }
          .idx-form input:focus, .idx-form textarea:focus { outline: none; border-color: #2563eb; box-shadow: 0 0 0 2px rgba(37,99,235,0.15); }
          .idx-form textarea { resize: vertical; min-height: 80px; }
          .idx-form-actions { display: flex; gap: 8px; margin-top: 4px; }
          .idx-form-submit { padding: 8px 20px; background: #2563eb; color: #fff; border: none; border-radius: 4px; font-size: 14px; font-weight: 600; cursor: pointer; }
          .idx-form-submit:hover { background: #1d4ed8; }
          .idx-form-submit:disabled { background: #93c5fd; cursor: not-allowed; }
          .idx-form-cancel { padding: 8px 16px; background: none; border: 1px solid #d0d0d0; border-radius: 4px; font-size: 14px; cursor: pointer; color: #666; }
          .idx-form-cancel:hover { background: #f6f8fa; }
          .idx-form-error { color: #c62828; font-size: 13px; margin-bottom: 8px; }
          .idx-dropzone { border: 2px dashed #d0d0d0; border-radius: 6px; padding: 16px; text-align: center; margin-bottom: 12px; transition: border-color 0.15s, background 0.15s; }
          .idx-dropzone-active { border-color: #2563eb; background: #f0f6ff; }
          .idx-dropzone-text { font-size: 13px; color: #888; }
          .idx-dropzone-text a { color: #2563eb; text-decoration: none; cursor: pointer; }
          .idx-dropzone-text a:hover { text-decoration: underline; }
          .idx-file-names { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 8px; }
          .idx-file-tag { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; background: #eff6ff; border-radius: 4px; font-size: 12px; color: #333; }
          .idx-file-tag a { color: #999; text-decoration: none; font-size: 14px; }
          .idx-file-tag a:hover { color: #c62828; }
        </style>
        </head>
        <body>
        <div class="idx-header">Machinascripta</div>
        <div class="idx-container">
          <div class="idx-books">
            <div class="idx-books-list" id="idx-books"></div>
            <button class="idx-write-btn" id="idx-write-btn">+ Write a new book</button>
          </div>
          <div class="idx-toc" id="idx-toc">
            <div class="idx-toc-empty">Select a book to view its table of contents</div>
          </div>
        </div>
        <script>
        var books = __BOOKS_JSON__;
        var writeJobs = __WRITE_JOBS_JSON__;
        var listEl = document.getElementById('idx-books');
        var tocEl = document.getElementById('idx-toc');
        var activeEl = null;
        var jobElements = {};

        function renderBooks() {
          listEl.innerHTML = '';
          books.forEach(function(book) {
            var el = createBookEl(book);
            listEl.appendChild(el);
          });
          writeJobs.forEach(function(job) {
            if (job.status !== 'done' && !books.find(function(b) { return b.slug === job.slug; })) {
              var el = createJobEl(job);
              jobElements[job.slug] = el;
              listEl.appendChild(el);
            }
          });
          if (books.length === 1 && writeJobs.length === 0) listEl.children[0].click();
        }

        function createBookEl(book) {
          var el = document.createElement('div');
          el.className = 'idx-book';
          el.dataset.slug = book.slug;
          var badge = '';
          var job = writeJobs.find(function(j) { return j.slug === book.slug && j.status === 'done'; });
          if (job) badge = ' <span class="idx-badge idx-badge-done">New!</span>';
          el.innerHTML = '<div class="idx-book-title">' + esc(book.title) + badge + '</div>' +
            (book.author ? '<div class="idx-book-author">' + esc(book.author) + '</div>' : '') +
            (book.updated_at ? '<div class="idx-book-updated">' + esc(book.updated_at) + '</div>' : '');
          el.addEventListener('click', function() {
            if (activeEl) activeEl.classList.remove('active');
            el.classList.add('active');
            activeEl = el;
            showToc(book);
          });
          return el;
        }

        function createJobEl(job) {
          var el = document.createElement('div');
          el.className = 'idx-book';
          el.dataset.slug = job.slug;
          var badgeClass = job.status === 'writing' ? 'idx-badge-writing' : (job.status === 'error' ? 'idx-badge-error' : 'idx-badge-done');
          var badgeText = job.status === 'writing' ? 'Writing\u2026' : (job.status === 'error' ? 'Error' : 'New!');
          el.innerHTML = '<div class="idx-book-title">' + esc(job.title) + ' <span class="idx-badge ' + badgeClass + '">' + badgeText + '</span></div>';
          if (job.status === 'error') {
            el.addEventListener('click', function() {
              if (activeEl) activeEl.classList.remove('active');
              el.classList.add('active');
              activeEl = el;
              tocEl.innerHTML = '<div class="idx-form"><h2>' + esc(job.title) + '</h2><div class="idx-form-error">Error: ' + esc(job.error || 'Unknown error') + '</div></div>';
            });
          }
          return el;
        }

        renderBooks();

        // Write form
        document.getElementById('idx-write-btn').addEventListener('click', function() {
          if (activeEl) activeEl.classList.remove('active');
          activeEl = null;
          showWriteForm();
        });

        function showWriteForm() {
          tocEl.innerHTML =
            '<div class="idx-form">' +
            '<h2>Write a new book</h2>' +
            '<div class="idx-form-error" id="idx-form-err" style="display:none"></div>' +
            '<label for="wf-dir">Directory *</label>' +
            '<input id="wf-dir" placeholder="ruby-intro">' +
            '<label for="wf-title">Title *</label>' +
            '<input id="wf-title" placeholder="Ruby入門">' +
            '<label for="wf-lang">Language</label>' +
            '<input id="wf-lang" value="ja">' +
            '<label for="wf-audience">Audience</label>' +
            '<input id="wf-audience" placeholder="初心者">' +
            '<label for="wf-notes">Notes</label>' +
            '<textarea id="wf-notes" placeholder="5章くらいで"></textarea>' +
            '<label>Reference Files</label>' +
            '<div class="idx-dropzone" id="wf-dropzone">' +
              '<input type="file" id="wf-files" multiple style="display:none">' +
              '<span class="idx-dropzone-text">Drop files here or <a href="#" id="wf-browse">browse</a></span>' +
              '<div class="idx-file-names" id="wf-file-names"></div>' +
            '</div>' +
            '<div class="idx-form-actions">' +
            '<button class="idx-form-submit" id="wf-submit">Start Writing</button>' +
            '<button class="idx-form-cancel" id="wf-cancel">Cancel</button>' +
            '</div></div>';

          document.getElementById('wf-cancel').addEventListener('click', function() {
            tocEl.innerHTML = '<div class="idx-toc-empty">Select a book to view its table of contents</div>';
          });

          var wfPendingFiles = [];
          var wfDropzone = document.getElementById('wf-dropzone');
          var wfFileInput = document.getElementById('wf-files');
          var wfFileNames = document.getElementById('wf-file-names');

          document.getElementById('wf-browse').addEventListener('click', function(e) {
            e.preventDefault();
            wfFileInput.click();
          });

          wfFileInput.addEventListener('change', function() {
            addPendingFiles(wfFileInput.files, wfPendingFiles, wfFileNames);
          });

          wfDropzone.addEventListener('dragover', function(e) {
            e.preventDefault();
            wfDropzone.classList.add('idx-dropzone-active');
          });
          wfDropzone.addEventListener('dragleave', function() {
            wfDropzone.classList.remove('idx-dropzone-active');
          });
          wfDropzone.addEventListener('drop', function(e) {
            e.preventDefault();
            wfDropzone.classList.remove('idx-dropzone-active');
            addPendingFiles(e.dataTransfer.files, wfPendingFiles, wfFileNames);
          });

          document.getElementById('wf-submit').addEventListener('click', function() {
            var dir = document.getElementById('wf-dir').value.trim();
            var title = document.getElementById('wf-title').value.trim();
            var errEl = document.getElementById('idx-form-err');
            errEl.style.display = 'none';

            if (!dir || !title) {
              errEl.textContent = 'Directory and Title are required.';
              errEl.style.display = 'block';
              return;
            }
            if (/[\/\\]/.test(dir) || dir.startsWith('.')) {
              errEl.textContent = 'Invalid directory name.';
              errEl.style.display = 'block';
              return;
            }

            var btn = document.getElementById('wf-submit');
            btn.disabled = true;
            btn.textContent = 'Starting\u2026';

            readFilesAsBase64(wfPendingFiles).then(function(filesData) {
            var payload = {
                directory: dir,
                title: title,
                language: document.getElementById('wf-lang').value.trim() || 'ja',
                audience: document.getElementById('wf-audience').value.trim(),
                notes: document.getElementById('wf-notes').value.trim()
            };
            if (filesData.length > 0) payload.files = filesData;

            return fetch('/_ligarb/write', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(payload)
            });
            }).then(function(r) { return r.json().then(function(d) { return { ok: r.ok, data: d }; }); })
            .then(function(result) {
              if (!result.ok) {
                errEl.textContent = result.data.error || 'Request failed';
                errEl.style.display = 'block';
                btn.disabled = false;
                btn.textContent = 'Start Writing';
                return;
              }
              var job = { slug: result.data.slug, title: result.data.title, status: 'writing' };
              writeJobs.push(job);
              var el = createJobEl(job);
              jobElements[job.slug] = el;
              listEl.appendChild(el);
              tocEl.innerHTML = '<div class="idx-toc-empty">Writing "' + esc(title) + '"\u2026 This may take a few minutes.</div>';
            })
            .catch(function(e) {
              errEl.textContent = 'Network error: ' + e.message;
              errEl.style.display = 'block';
              btn.disabled = false;
              btn.textContent = 'Start Writing';
            });
          });
        }

        function showToc(book) {
          var h = '<div class="idx-toc-title"><a href="/' + book.slug + '/" target="_blank">' + esc(book.title) + ' &rarr;</a></div>';
          book.toc.forEach(function(e) {
            if (e.type === 'part') {
              h += '<div class="idx-toc-part">' + esc(e.title) + '</div>';
            } else if (e.type === 'appendix_header') {
              h += '<div class="idx-toc-part">' + esc(e.label) + '</div>';
            } else if (e.type === 'cover') {
              h += '<a class="idx-toc-ch idx-toc-cover" href="/' + book.slug + '/#' + e.slug + '" target="_blank">' + esc(e.title) + '</a>';
            } else {
              h += '<a class="idx-toc-ch" href="/' + book.slug + '/#' + e.slug + '" target="_blank">' + esc(e.title) + '</a>';
            }
          });
          tocEl.innerHTML = h;
        }

        function esc(s) {
          var d = document.createElement('div');
          d.textContent = s || '';
          return d.innerHTML;
        }

        function addPendingFiles(fileList, pending, namesEl) {
          for (var i = 0; i < fileList.length; i++) {
            pending.push(fileList[i]);
          }
          renderFileNames(pending, namesEl);
        }

        function renderFileNames(pending, namesEl) {
          namesEl.innerHTML = '';
          pending.forEach(function(f, i) {
            var span = document.createElement('span');
            span.className = 'idx-file-tag';
            span.innerHTML = esc(f.name) + ' <a href="#" data-idx="' + i + '">&times;</a>';
            span.querySelector('a').addEventListener('click', function(e) {
              e.preventDefault();
              pending.splice(parseInt(this.dataset.idx), 1);
              renderFileNames(pending, namesEl);
            });
            namesEl.appendChild(span);
          });
        }

        function readFilesAsBase64(files) {
          if (!files || files.length === 0) return Promise.resolve([]);
          var promises = files.map(function(f) {
            return new Promise(function(resolve) {
              var reader = new FileReader();
              reader.onload = function() {
                var base64 = reader.result.split(',')[1] || '';
                resolve({ name: f.name, data: base64 });
              };
              reader.readAsDataURL(f);
            });
          });
          return Promise.all(promises);
        }

        // SSE for write updates
        var evtSource = new EventSource('/_ligarb/events');
        evtSource.addEventListener('write_updated', function(e) {
          var jobs = JSON.parse(e.data);
          writeJobs = jobs;

          // Reload page to get full book data when a job completes
          var hasDone = jobs.find(function(j) { return j.status === 'done'; });
          if (hasDone) {
            // Fetch fresh books data to get TOC etc.
            location.reload();
            return;
          }

          // Update existing job elements
          jobs.forEach(function(job) {
            var existing = jobElements[job.slug];
            if (existing) {
              var badgeClass = job.status === 'writing' ? 'idx-badge-writing' : (job.status === 'error' ? 'idx-badge-error' : 'idx-badge-done');
              var badgeText = job.status === 'writing' ? 'Writing\u2026' : (job.status === 'error' ? 'Error' : 'New!');
              existing.querySelector('.idx-book-title').innerHTML = esc(job.title) + ' <span class="idx-badge ' + badgeClass + '">' + badgeText + '</span>';
            }
          });
        });
        </script>
        </body>
        </html>
      HTML

      # Escape </ to prevent script injection inside <script> tag
      html = html.sub("__BOOKS_JSON__", books_json.gsub("</", '<\/'))
      html = html.sub("__WRITE_JOBS_JSON__", write_jobs_json.gsub("</", '<\/'))
      res.body = html
      res["Content-Type"] = "text/html; charset=utf-8"
    end

    def build_toc(book)
      toc = []
      chapter_num = 0
      appendix_idx = 0

      book.config.structure.each do |entry|
        case entry.type
        when :cover
          title = first_heading(entry.path) || "Cover"
          slug = file_slug(entry.path)
          toc << { type: "cover", title: title, slug: slug }
        when :chapter
          chapter_num += 1
          title = first_heading(entry.path) || File.basename(entry.path, ".md")
          slug = file_slug(entry.path)
          prefix = book.config.chapter_numbers ? "#{chapter_num}. " : ""
          toc << { type: "chapter", title: "#{prefix}#{title}", slug: slug }
        when :part
          part_title = first_heading(entry.path) || "Part"
          toc << { type: "part", title: part_title }
          (entry.children || []).each do |ch|
            chapter_num += 1
            title = first_heading(ch.path) || File.basename(ch.path, ".md")
            slug = file_slug(ch.path)
            prefix = book.config.chapter_numbers ? "#{chapter_num}. " : ""
            toc << { type: "chapter", title: "#{prefix}#{title}", slug: slug }
          end
        when :appendix_group
          toc << { type: "appendix_header", label: book.config.appendix_label }
          (entry.children || []).each_with_index do |ch, i|
            title = first_heading(ch.path) || File.basename(ch.path, ".md")
            slug = file_slug(ch.path)
            letter = ("A".ord + appendix_idx + i).chr
            toc << { type: "chapter", title: "#{book.config.appendix_label} #{letter}. #{title}", slug: slug }
          end
          appendix_idx += (entry.children || []).size
        end
      end

      toc
    end

    def first_heading(path)
      return nil unless path && File.exist?(path)
      File.foreach(path) do |line|
        return $1.strip if line =~ /\A#\s+(.+)/
      end
      nil
    end

    def file_slug(path)
      File.basename(path, ".md").gsub(/[^a-zA-Z0-9_-]/, "-")
    end

    # ── API routing ──

    def csrf_safe?(req)
      return true if req.request_method == "GET"

      origin = req["Origin"]
      if origin && !origin.empty?
        return origin == "http://localhost:#{@port}" ||
               origin == "http://127.0.0.1:#{@port}"
      end

      referer = req["Referer"]
      if referer && !referer.empty?
        uri = URI.parse(referer) rescue nil
        return uri && %w[localhost 127.0.0.1].include?(uri.host) && uri.port == @port
      end

      false
    end

    def handle_api(req, res)
      unless csrf_safe?(req)
        res.status = 403
        res["Content-Type"] = "application/json; charset=utf-8"
        res.body = JSON.generate({ error: "CSRF check failed: request must originate from localhost" })
        return
      end

      method = req.request_method
      path = req.path.sub(%r{^/_ligarb}, "")

      # Shared assets (both modes)
      if method == "GET" && path =~ %r{^/assets/(.+)$}
        serve_asset($1, res)
        return
      end

      # Global write API (multi-book mode)
      if @multi
        if method == "GET" && path == "/events"
          handle_sse(nil, req, res)
          return
        end
        if method == "POST" && path == "/write"
          res["Content-Type"] = "application/json; charset=utf-8"
          begin
            api_start_write(req, res)
          rescue => e
            res.status = 500
            res.body = JSON.generate({ error: e.message })
          end
          return
        end
        if method == "GET" && path == "/write/status"
          res["Content-Type"] = "application/json; charset=utf-8"
          api_write_status(res)
          return
        end
      end

      # Resolve book
      if @multi
        unless path =~ %r{^/([^/]+)(/.*)?$}
          res["Content-Type"] = "application/json; charset=utf-8"
          not_found(res)
          return
        end
        book = @books[$1]
        unless book
          res["Content-Type"] = "application/json; charset=utf-8"
          not_found(res)
          return
        end
        api_path = $2 || "/"
      else
        book = @books.values.first
        api_path = path
      end

      # SSE endpoint
      if method == "GET" && api_path == "/events"
        handle_sse(book.slug, req, res)
        return
      end

      res["Content-Type"] = "application/json; charset=utf-8"

      begin
        if method == "GET" && api_path == "/status"
          api_status(book, res)
        elsif method == "GET" && api_path == "/reviews"
          api_list_reviews(book, res)
        elsif method == "POST" && api_path == "/reviews"
          api_create_review(book, req, res)
        elsif method == "GET" && api_path =~ %r{^/reviews/([0-9a-f-]+)$}
          api_get_review(book, $1, res)
        elsif method == "POST" && api_path =~ %r{^/reviews/([0-9a-f-]+)/messages$}
          api_add_message(book, $1, req, res)
        elsif method == "POST" && api_path =~ %r{^/reviews/([0-9a-f-]+)/approve$}
          api_approve(book, $1, res)
        elsif method == "POST" && api_path =~ %r{^/reviews/([0-9a-f-]+)/close$}
          api_delete_review(book, $1, res)
        else
          not_found(res)
        end
      rescue => e
        res.status = 500
        res.body = JSON.generate({ error: e.message })
      end
    end

    # ── API handlers ──

    def api_status(book, res)
      html_path = File.join(book.build_dir, "index.html")
      mtime = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
      res.body = JSON.generate({ mtime: mtime })
    end

    def api_list_reviews(book, res)
      res.body = JSON.generate(book.store.list)
    end

    def api_get_review(book, id, res)
      review = book.store.get(id)
      if review
        res.body = JSON.generate(review)
      else
        not_found(res)
      end
    end

    def api_create_review(book, req, res)
      body = parse_body(req)

      context = body["context"] || {}
      message = body["message"]

      unless message && !message.strip.empty?
        res.status = 400
        res.body = JSON.generate({ error: "message is required" })
        return
      end

      context["source_file"] = resolve_source_file(book.config, context["chapter_slug"])

      saved = save_uploaded_files(body["files"], book.config.base_dir)
      context["uploaded_files"] = saved unless saved.empty?

      review = book.store.create(context: context, message: message)
      start_claude_review(book, review["id"])

      res.status = 201
      res.body = JSON.generate(review)
    end

    def api_add_message(book, id, req, res)
      review = book.store.get(id)
      unless review
        not_found(res)
        return
      end

      body = parse_body(req)
      message = body["message"]

      unless message && !message.strip.empty?
        res.status = 400
        res.body = JSON.generate({ error: "message is required" })
        return
      end

      saved = save_uploaded_files(body["files"], book.config.base_dir)
      book.store.update_context_files(id, saved) unless saved.empty?

      book.store.add_message(id, role: "user", content: message)
      start_claude_review(book, id)

      review = book.store.get(id)
      res.body = JSON.generate(review)
    end

    def api_approve(book, id, res)
      review = book.store.get(id)
      unless review
        not_found(res)
        return
      end

      log "Approve: applying patches for review #{id}"

      result = enqueue_sync { book.claude.apply_patches(review) }

      if result["error"] && result["error"].include?("rebuild failed")
        # Build failed — feed the error back to Claude for a retry
        log "Approve: build failed, requesting fix from Claude"
        error_msg = result["error"]
        book.store.add_message(id, role: "assistant", content: "Error: #{error_msg}")
        sse_broadcast("review_updated", { id: id }, slug: book.slug)

        retry_msg = "The patches were applied but the build failed with this error:\n\n" \
                    "#{error_msg}\n\n" \
                    "Please provide corrected patches that fix this issue."
        book.store.add_message(id, role: "user", content: retry_msg)
        sse_broadcast("review_updated", { id: id }, slug: book.slug)

        # Re-run Claude with the updated conversation
        review = book.store.get(id)
        prompt = book.claude.review_prompt(review)
        claude_result = book.claude.run(prompt)

        if claude_result["error"]
          log "Approve: retry Claude error: #{claude_result["error"]}"
          book.store.add_message(id, role: "assistant", content: "Error: #{claude_result["error"]}")
          book.store.update_status(id, "open")
        else
          log "Approve: Claude provided fix, retrying patches"
          book.store.add_message(id, role: "assistant", content: claude_result["text"])
          sse_broadcast("review_updated", { id: id }, slug: book.slug)

          # Retry applying patches with the new response
          review = book.store.get(id)
          retry_result = enqueue_sync { book.claude.apply_patches(review) }

          if retry_result["error"]
            log "Approve: retry failed: #{retry_result["error"]}"
            book.store.add_message(id, role: "assistant", content: "Retry failed: #{retry_result["error"]}")
            book.store.update_status(id, "open")
          else
            log "Approve: retry succeeded: #{retry_result["text"]}"
            book.store.add_message(id, role: "assistant", content: retry_result["text"])
            book.store.update_status(id, "applied")
          end
        end
      elsif result["error"]
        log "Approve: error: #{result["error"]}"
        book.store.add_message(id, role: "assistant", content: "Error: #{result["error"]}")
        book.store.update_status(id, "open")
      else
        log "Approve: #{result["text"]}"
        book.store.add_message(id, role: "assistant", content: result["text"])
        book.store.update_status(id, "applied")
      end

      sse_broadcast("review_updated", { id: id }, slug: book.slug)
      review = book.store.get(id)
      res.body = JSON.generate(review)
    end

    def api_delete_review(book, id, res)
      review = book.store.get(id)
      unless review
        not_found(res)
        return
      end

      book.store.update_status(id, "closed")
      sse_broadcast("review_updated", { id: id }, slug: book.slug)

      review = book.store.get(id)
      res.body = JSON.generate(review)
    end

    def serve_asset(filename, res)
      unless INJECTED_ASSETS.include?(filename)
        not_found(res)
        return
      end

      path = File.join(@assets_dir, filename)
      unless File.exist?(path)
        not_found(res)
        return
      end

      res.body = File.read(path)
      res["Content-Type"] = mime_type(path)
    end

    def start_claude_review(book, review_id)
      Thread.new do
        log "Review: starting Claude review for #{review_id}"
        begin
          review = book.store.get(review_id)
          next unless review

          case book.claude.installed?
          when :not_found
            book.store.add_message(review_id, role: "assistant",
              content: "Error: 'claude' command not found. Install Claude Code to enable AI reviews.")
            next
          when :version_failed
            book.store.add_message(review_id, role: "assistant",
              content: "Error: 'claude' command was found but failed to run. Check your Claude Code installation.")
            next
          end

          prompt = book.claude.review_prompt(review)
          result = book.claude.run(prompt)

          if result["error"]
            log "Review: Claude error: #{result["error"]}"
            book.store.add_message(review_id, role: "assistant", content: "Error: #{result["error"]}")
          else
            log "Review: Claude responded"
            book.store.add_message(review_id, role: "assistant", content: result["text"])
          end
        rescue => e
          log "Review: exception: #{e.message}"
          book.store.add_message(review_id, role: "assistant", content: "Error: #{e.message}")
        ensure
          sse_broadcast("review_updated", { id: review_id }, slug: book.slug)
        end
      end
    end

    # ── Write API ──

    def api_start_write(req, res)
      body = parse_body(req)
      directory = body["directory"].to_s.strip
      title = body["title"].to_s.strip

      if directory.empty? || title.empty?
        res.status = 400
        res.body = JSON.generate({ error: "directory and title are required" })
        return
      end

      if directory.include?("/") || directory.include?("\\") || directory.start_with?(".")
        res.status = 400
        res.body = JSON.generate({ error: "invalid directory name" })
        return
      end

      if @books.key?(directory)
        res.status = 409
        res.body = JSON.generate({ error: "a book with slug '#{directory}' already exists" })
        return
      end

      target_dir = File.join(Dir.pwd, directory)
      if Dir.exist?(target_dir)
        res.status = 409
        res.body = JSON.generate({ error: "directory '#{directory}' already exists" })
        return
      end

      @write_mutex.synchronize do
        if @write_jobs.key?(directory)
          res.status = 409
          res.body = JSON.generate({ error: "a write job for '#{directory}' is already running" })
          return
        end
        @write_jobs[directory] = { title: title, status: "writing", error: nil }
      end

      # Write brief.yml
      FileUtils.mkdir_p(target_dir)
      brief_path = File.join(target_dir, "brief.yml")
      brief_data = { "title" => title, "language" => body["language"] || "ja" }
      brief_data["audience"] = body["audience"] if body["audience"] && !body["audience"].to_s.strip.empty?
      brief_data["notes"] = body["notes"] if body["notes"] && !body["notes"].to_s.strip.empty?

      saved = save_uploaded_files(body["files"], target_dir)
      if saved.any?
        brief_data["sources"] = saved.map { |f| { "path" => f["path"], "label" => f["label"] } }
      end

      File.write(brief_path, YAML.dump(brief_data))

      sse_broadcast("write_updated", write_jobs_data, slug: nil)

      # Run write job via operation queue (async)
      enqueue_async do
        begin
          log "Write: starting for '#{directory}' (title: #{title})"
          require_relative "writer"
          writer = Writer.new(brief_path, no_build: true)
          writer.run

          book_yml_path = File.join(target_dir, "book.yml")
          require_relative "builder"
          Builder.new(book_yml_path).build

          # Git init + commit for the generated book
          unless system("git", "rev-parse", "--git-dir", out: File::NULL, err: File::NULL, chdir: target_dir)
            gitignore = File.join(target_dir, ".gitignore")
            File.write(gitignore, "# Generated by ligarb - remove lines as needed\nbuild/\n.ligarb/\n") unless File.exist?(gitignore)
            system("git", "init", chdir: target_dir, out: File::NULL, err: File::NULL)
          end
          system("git", "add", "-A", chdir: target_dir, out: File::NULL, err: File::NULL)
          system("git", "commit", "-m", "[ligarb] Generate book: #{title}",
                 chdir: target_dir, out: File::NULL, err: File::NULL)

          # Register the new book
          config = Config.new(book_yml_path)
          book = BookEntry.new(
            slug: directory,
            config: config,
            config_path: File.expand_path(book_yml_path),
            build_dir: config.output_path,
            store: ReviewStore.new(config.base_dir),
            claude: ClaudeRunner.new(config)
          )
          @books[directory] = book
          start_build_watcher(book)

          @write_mutex.synchronize { @write_jobs[directory][:status] = "done" }
          log "Write: completed for '#{directory}'"
        rescue => e
          @write_mutex.synchronize do
            @write_jobs[directory][:status] = "error"
            @write_jobs[directory][:error] = e.message
          end
          log "Write: error for '#{directory}': #{e.message}"
        ensure
          sse_broadcast("write_updated", write_jobs_data, slug: nil)
        end
      end

      res.status = 201
      res.body = JSON.generate({ slug: directory, title: title, status: "writing" })
    end

    def api_write_status(res)
      res.body = JSON.generate(write_jobs_data)
    end

    def write_jobs_data
      @write_mutex.synchronize do
        @write_jobs.map { |slug, job| { slug: slug, title: job[:title], status: job[:status], error: job[:error] } }
      end
    end

    # ── Helpers ──

    MAX_UPLOAD_FILE_SIZE = 10 * 1024 * 1024 # 10MB per file

    def save_uploaded_files(files_array, base_dir)
      return [] unless files_array.is_a?(Array) && !files_array.empty?

      upload_dir = File.join(base_dir, ".ligarb", "uploads")
      FileUtils.mkdir_p(upload_dir)

      files_array.filter_map do |file|
        name = file["name"].to_s.strip
        data = file["data"].to_s
        next if name.empty? || data.empty?

        decoded = Base64.decode64(data)
        if decoded.bytesize > MAX_UPLOAD_FILE_SIZE
          log "Upload rejected: #{name} exceeds #{MAX_UPLOAD_FILE_SIZE} bytes"
          next
        end

        # Sanitize filename
        safe_name = File.basename(name).gsub(/[^a-zA-Z0-9._-]/, "_")
        short_id = SecureRandom.hex(4)
        filename = "#{short_id}-#{safe_name}"
        dest = File.join(upload_dir, filename)

        File.binwrite(dest, decoded)
        { "path" => File.expand_path(dest), "label" => name }
      end
    end

    def resolve_source_file(config, chapter_slug)
      return nil unless chapter_slug

      config.all_file_paths.find { |path|
        slug = File.basename(path, ".md").gsub(/[^a-zA-Z0-9_-]/, "-")
        slug == chapter_slug
      }
    end

    def parse_body(req)
      JSON.parse(req.body || "{}")
    rescue JSON::ParserError
      {}
    end

    def not_found(res)
      res.status = 404
      res.body = JSON.generate({ error: "not found" })
    end

    def log(msg)
      $stderr.puts "[ligarb #{Time.now.strftime('%H:%M:%S')}] #{msg}"
    end

    def escape_html(str)
      str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    def escape_js_string(str)
      str.to_s.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'").gsub('"', '\\\\"')
         .gsub("\n", "\\n").gsub("\r", "\\r").gsub("</", '<\\/')
    end

    def mime_type(path)
      case File.extname(path).downcase
      when ".html" then "text/html; charset=utf-8"
      when ".css"  then "text/css; charset=utf-8"
      when ".js"   then "application/javascript; charset=utf-8"
      when ".json" then "application/json; charset=utf-8"
      when ".png"  then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif"  then "image/gif"
      when ".svg"  then "image/svg+xml"
      when ".woff" then "font/woff"
      when ".woff2" then "font/woff2"
      else "application/octet-stream"
      end
    end
  end
end
