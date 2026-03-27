# Preview and Review

## ligarb serve -- Local Server

> [!WARNING]
> `ligarb serve` is for local development only. Do not use it for production or public-facing deployments.

The [`ligarb serve`](#index:ligarb serve) command serves the built book via a local web server.
A build is automatically run at startup, so there is no need to run `ligarb build` beforehand.

```bash
ligarb serve                    # Serve at http://localhost:3000
ligarb serve --port 8080        # Specify port
ligarb serve path/to/book.yml   # Specify book.yml path
```

## Live Reload

When you edit the source and run `ligarb build`, a reload button appears in the bottom-right corner of the browser.
Clicking it updates the content while preserving the scroll position.

On Linux, [inotify](#index:inotify) is used to detect changes to `index.html` immediately.
On other operating systems, changes are detected via 2-second interval polling.

## Review UI

You can add comments to the book text in the browser, discuss with [Claude](#index:AI integration), and apply approved changes to the source files.

> [!NOTE]
> The review feature requires the [Claude Code](https://claude.com/claude-code) CLI (`claude` command).
> Server delivery and live reload work without it.

### Comment Flow

1. **Text selection**: Drag to select text in the book content, and a "Comment" button appears
2. **Comment input**: Click the button to open a side panel for entering your comment
3. **Claude review**: Submitting a comment triggers Claude (Opus) to read `book.yml` and reference all chapters and bibliography files as needed, returning improvement suggestions. Patches spanning multiple chapters can also be generated
4. **Patch review**: Use the "Show patch" button in the message to view the proposed changes as a diff (red = deletion, green = addition)
5. **Discussion**: Reply to the suggestion to continue the discussion

### Approve and Dismiss

- **Approve**: Applies the patch to source files and triggers an automatic rebuild. Claude is not called again, so this completes instantly
- **Dismiss**: Closes the thread (no changes are applied)

### Managing Reviews

Click the mail icon in the bottom-right corner to open the review list panel.
When there are unresolved threads, the icon is highlighted in yellow with a badge showing the count.

Reviews in progress are not interrupted when the panel is closed.
Click a thread in the list to resume the conversation at any time.

### Data Storage

Review data is saved as JSON files in the `.ligarb/reviews/` directory.
Decide whether to add it to `.gitignore` based on your project needs.

```
.ligarb/
└── reviews/
    ├── 3f8a1b2c-...json
    └── 7d4e5f6a-...json
```

## Internal API

The server provides an internal API under the `/_ligarb/` prefix.
The frontend JS uses these, but they can also be used for integration with external tools.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/_ligarb/events` | SSE stream (`build_updated` / `review_updated` / `write_updated`) |
| GET | `/_ligarb/reviews` | Thread list |
| POST | `/_ligarb/reviews` | Create new thread |
| POST | `/_ligarb/reviews/:id/approve` | Apply patch & rebuild |
