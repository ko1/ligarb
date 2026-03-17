# frozen_string_literal: true

# Thin Fiddle wrapper for Linux inotify(7).
# Non-Linux platforms will get LoadError from dlsym lookup.

require "fiddle"

module Ligarb
  module Inotify
    LIBC = Fiddle.dlopen(nil)

    InotifyInit1 = Fiddle::Function.new(
      LIBC["inotify_init1"],
      [Fiddle::TYPE_INT],
      Fiddle::TYPE_INT
    )

    InotifyAddWatch = Fiddle::Function.new(
      LIBC["inotify_add_watch"],
      [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
      Fiddle::TYPE_INT
    )

    InotifyRmWatch = Fiddle::Function.new(
      LIBC["inotify_rm_watch"],
      [Fiddle::TYPE_INT, Fiddle::TYPE_INT],
      Fiddle::TYPE_INT
    )

    # inotify event masks
    IN_CLOSE_WRITE = 0x00000008
    IN_CLOEXEC     = 0x00080000  # O_CLOEXEC on x86_64

    # struct inotify_event fixed part: int wd, uint32 mask, uint32 cookie, uint32 len
    EVENT_HEADER_SIZE = 16

    # Watch a file for writes. Yields each time the file is written and closed.
    # Blocks the calling thread. Caller should wrap in Thread.new.
    def self.watch_file(path, &block)
      fd = InotifyInit1.call(IN_CLOEXEC)
      raise SystemCallError.new("inotify_init1", Fiddle.last_error) if fd < 0

      io = IO.for_fd(fd, autoclose: true)
      wd = add_watch(fd, path)

      loop do
        # IO.select releases GVL while waiting
        IO.select([io])
        buf = io.read_nonblock(4096, exception: false)
        next if buf == :wait_readable || buf.nil?

        # Parse events — may contain multiple events
        offset = 0
        while offset + EVENT_HEADER_SIZE <= buf.bytesize
          _wd, mask, _cookie, name_len = buf.byteslice(offset, EVENT_HEADER_SIZE).unpack("iIII")
          offset += EVENT_HEADER_SIZE + name_len

          if mask & IN_CLOSE_WRITE != 0
            block.call
          end
        end
      rescue IOError, Errno::EBADF
        break
      end
    ensure
      io&.close rescue nil
    end

    def self.add_watch(fd, path)
      wd = InotifyAddWatch.call(fd, path, IN_CLOSE_WRITE)
      raise SystemCallError.new("inotify_add_watch: #{path}", Fiddle.last_error) if wd < 0
      wd
    end
  end
end
