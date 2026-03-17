# frozen_string_literal: true

require "webrick"
require "json"
require_relative "config"
require_relative "review_store"
require_relative "claude_runner"

module Ligarb
  class Server
    INJECTED_ASSETS = %w[serve.js review.js review.css].freeze

    def initialize(config_path, port: 3000)
      @config = Config.new(config_path)
      @port = port
      @build_dir = @config.output_path
      @store = ReviewStore.new(@config.base_dir)
      @claude = ClaudeRunner.new(@config)
      @assets_dir = File.join(File.dirname(__FILE__), "..", "..", "assets")
      @sse_clients = []
      @sse_mutex = Mutex.new
    end

    def start
      config_path = File.join(@config.base_dir, "book.yml")
      puts "Building..."
      require_relative "builder"
      Builder.new(config_path).build

      server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO),
        AccessLog: [[File.open(File::NULL, "w"), WEBrick::AccessLog::COMMON_LOG_FORMAT]]
      )

      # API routes under /_ligarb/
      server.mount_proc("/_ligarb/") { |req, res| handle_api(req, res) }

      # Serve index.html with injection at root
      server.mount_proc("/") { |req, res| handle_static(req, res) }

      trap("INT") { Thread.new { close_sse_clients; server.shutdown } }
      trap("TERM") { Thread.new { close_sse_clients; server.shutdown } }

      # Background thread to watch build output for changes
      start_build_watcher

      puts "Serving #{@config.title} at http://localhost:#{@port}"
      puts "  Build directory: #{@build_dir}"
      puts "  Press Ctrl+C to stop"

      server.start
    end

    private

    # ── SSE (Server-Sent Events) ──

    def close_sse_clients
      @sse_mutex.synchronize do
        @sse_clients.each { |q| q.push(:close) rescue nil }
        @sse_clients.clear
      end
    end

    def sse_broadcast(event, data)
      json = JSON.generate(data)
      message = "event: #{event}\ndata: #{json}\n\n"
      @sse_mutex.synchronize do
        @sse_clients.reject! do |queue|
          begin
            queue.push(message, true) # non-blocking push
            false
          rescue ThreadError
            true # queue full, drop client
          end
        end
      end
    end

    def handle_sse(_req, res)
      res["Content-Type"] = "text/event-stream"
      res["Cache-Control"] = "no-cache"
      res["Connection"] = "keep-alive"
      res["X-Accel-Buffering"] = "no"
      res.chunked = true

      queue = SizedQueue.new(50)
      @sse_mutex.synchronize { @sse_clients << queue }

      # WEBrick calls body.call(socket) for chunked proc bodies
      res.body = proc { |socket|
        begin
          socket.write("retry: 3000\n\n")
          loop do
            msg = queue.pop # blocks until message
            break if msg == :close
            socket.write(msg)
          end
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError
          # Client disconnected
        ensure
          @sse_mutex.synchronize { @sse_clients.delete(queue) }
        end
      }
    end

    def start_build_watcher
      html_path = File.join(@build_dir, "index.html")

      if use_inotify?
        $stderr.puts "[ligarb] Watching #{html_path} with inotify"
        Thread.new do
          Inotify.watch_file(html_path) do
            $stderr.puts "[ligarb] Build updated (inotify)"
            sse_broadcast("build_updated", { mtime: File.mtime(html_path).to_i })
          end
        rescue => e
          $stderr.puts "[ligarb] inotify watcher error: #{e.message}, falling back to polling"
          start_mtime_poller(html_path)
        end
      else
        start_mtime_poller(html_path)
      end
    end

    def start_mtime_poller(html_path)
      $stderr.puts "[ligarb] Watching #{html_path} with polling"
      Thread.new do
        last_mtime = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
        loop do
          sleep 2
          current = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
          if current > last_mtime
            last_mtime = current
            sse_broadcast("build_updated", { mtime: current })
          end
        rescue => e
          $stderr.puts "[ligarb] mtime watcher error: #{e.message}"
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

      if path == "/" || path == "/index.html"
        serve_injected_html(res)
        return
      end

      file_path = File.join(@build_dir, path)
      file_path = File.realpath(file_path) rescue nil

      if file_path && file_path.start_with?(File.realpath(@build_dir)) && File.file?(file_path)
        res.body = File.binread(file_path)
        res["Content-Type"] = mime_type(file_path)
      else
        res.status = 404
        res.body = "Not Found"
      end
    end

    def serve_injected_html(res)
      html_path = File.join(@build_dir, "index.html")
      html = File.read(html_path)

      css_tag = %(<link rel="stylesheet" href="/_ligarb/assets/review.css">)
      html.sub!("</head>", "#{css_tag}\n</head>")

      js_tags = %w[serve.js review.js].map { |f|
        %(<script src="/_ligarb/assets/#{f}"></script>)
      }.join("\n")
      html.sub!("</body>", "#{js_tags}\n</body>")

      res.body = html
      res["Content-Type"] = "text/html; charset=utf-8"
    end

    # ── API routing ──

    def handle_api(req, res)
      method = req.request_method
      path = req.path.sub(%r{^/_ligarb}, "")

      # SSE endpoint — handled separately (doesn't set JSON content-type)
      if method == "GET" && path == "/events"
        handle_sse(req, res)
        return
      end

      res["Content-Type"] = "application/json; charset=utf-8"

      begin
        if method == "GET" && path == "/status"
          api_status(res)
        elsif method == "GET" && path == "/reviews"
          api_list_reviews(res)
        elsif method == "POST" && path == "/reviews"
          api_create_review(req, res)
        elsif method == "GET" && path =~ %r{^/reviews/([0-9a-f-]+)$}
          api_get_review($1, res)
        elsif method == "POST" && path =~ %r{^/reviews/([0-9a-f-]+)/messages$}
          api_add_message($1, req, res)
        elsif method == "POST" && path =~ %r{^/reviews/([0-9a-f-]+)/approve$}
          api_approve($1, res)
        elsif method == "DELETE" && path =~ %r{^/reviews/([0-9a-f-]+)$}
          api_delete_review($1, res)
        elsif method == "GET" && path =~ %r{^/assets/(.+)$}
          serve_asset($1, res)
        else
          not_found(res)
        end
      rescue => e
        res.status = 500
        res.body = JSON.generate({ error: e.message })
      end
    end

    # ── API handlers ──

    def api_status(res)
      html_path = File.join(@build_dir, "index.html")
      mtime = File.exist?(html_path) ? File.mtime(html_path).to_i : 0
      res.body = JSON.generate({ mtime: mtime })
    end

    def api_list_reviews(res)
      res.body = JSON.generate(@store.list)
    end

    def api_get_review(id, res)
      review = @store.get(id)
      if review
        res.body = JSON.generate(review)
      else
        not_found(res)
      end
    end

    def api_create_review(req, res)
      body = parse_body(req)

      context = body["context"] || {}
      message = body["message"]

      unless message && !message.strip.empty?
        res.status = 400
        res.body = JSON.generate({ error: "message is required" })
        return
      end

      context["source_file"] = resolve_source_file(context["chapter_slug"])

      review = @store.create(context: context, message: message)
      start_claude_review(review["id"])

      res.status = 201
      res.body = JSON.generate(review)
    end

    def api_add_message(id, req, res)
      review = @store.get(id)
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

      @store.add_message(id, role: "user", content: message)
      start_claude_review(id)

      review = @store.get(id)
      res.body = JSON.generate(review)
    end

    def api_approve(id, res)
      review = @store.get(id)
      unless review
        not_found(res)
        return
      end

      $stderr.puts "[ligarb] Approve: applying patches for review #{id}"
      result = @claude.apply_patches(review)

      if result["error"]
        $stderr.puts "[ligarb] Approve: error: #{result["error"]}"
        @store.add_message(id, role: "assistant", content: "Error: #{result["error"]}")
        @store.update_status(id, "open")
      else
        $stderr.puts "[ligarb] Approve: #{result["text"]}"
        @store.add_message(id, role: "assistant", content: result["text"])
        @store.update_status(id, "applied")
      end

      sse_broadcast("review_updated", { id: id })
      review = @store.get(id)
      res.body = JSON.generate(review)
    end

    def api_delete_review(id, res)
      review = @store.get(id)
      unless review
        not_found(res)
        return
      end

      @store.update_status(id, "closed")
      sse_broadcast("review_updated", { id: id })

      review = @store.get(id)
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

    def start_claude_review(review_id)
      Thread.new do
        $stderr.puts "[ligarb] Review: starting Claude review for #{review_id}"
        begin
          review = @store.get(review_id)
          return unless review

          unless @claude.installed?
            @store.add_message(review_id, role: "assistant",
              content: "Error: 'claude' command not found. Install Claude Code to enable AI reviews.")
            sse_broadcast("review_updated", { id: review_id })
            return
          end

          prompt = @claude.review_prompt(review)
          result = @claude.run(prompt)

          if result["error"]
            $stderr.puts "[ligarb] Review: Claude error: #{result["error"]}"
            @store.add_message(review_id, role: "assistant", content: "Error: #{result["error"]}")
          else
            $stderr.puts "[ligarb] Review: Claude responded"
            @store.add_message(review_id, role: "assistant", content: result["text"])
          end
        rescue => e
          $stderr.puts "[ligarb] Review: exception: #{e.message}"
          @store.add_message(review_id, role: "assistant", content: "Error: #{e.message}")
        ensure
          sse_broadcast("review_updated", { id: review_id })
        end
      end
    end

    # ── Helpers ──

    def resolve_source_file(chapter_slug)
      return nil unless chapter_slug

      @config.all_file_paths.find { |path|
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
