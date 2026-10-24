# JSON Lines automation protocol v1

Run `QitesXmlLoader.exe --pipe` with redirected standard input and output. This mode creates no windows or message boxes and does not play a startup sound. It accepts one UTF-8 JSON object per line. Each command line is limited to 1 MiB of characters. Standard output contains JSON Lines only. A process-level failure is written as JSON to standard error and exits with code 1; normal shutdown exits with code 0. A failed command or operation is reported in a result and does not by itself terminate the session.

Optional startup switches are mutually exclusive: `--ignore-errors` sets `ErrorDecision: "reject"`; `--approve-errors` sets `ErrorDecision: "approve"`. Reject skips unresolved rows and denies automatic relocation/network access. Approve enables supported filename recovery and network paths and skips rows that remain unresolved. Neither policy invents an existing file or selects one of multiple existing candidates. `configure` accepts the same `ErrorDecision` values plus `"stop"`; stop resets these three options to safe defaults before applying any explicit settings in that request.

These policies handle track-reference decisions. They do not turn source-read failures, malformed XML, or output-write failures into success. A UNC source directory requires Approve or an explicit network-enabled configuration.

The application does not execute shell text from requests. Custom source-loader scripts are trusted application extensions and execute with the process's user permissions.

## Request and event envelopes

```json
{"id":"load-1","command":"load","args":{"path":"C:\\Music\\Library.xml"}}
```

`id` is echoed in replies. Clients must use distinct IDs and wait for a command's final `result` before starting the next processing operation. Control commands may be sent while an operation is active.

```json
{"type":"ready","id":null,"data":{"protocol":"qites-jsonl","version":1,"appVersion":"0.9"}}
{"type":"accepted","id":"load-1","data":{"operation":"Load"}}
{"type":"progress","id":"load-1","data":{"stage":"...","done":1,"total":10,"detail":"...","paused":false}}
{"type":"result","id":"load-1","data":{"ok":true,"state":"Complete","output":"","summary":"...","message":"","fileCheck":null,"playlists":3}}
```

Immediate queries return `data: {"ok": true, "value": ...}`. Rejected requests return `data: {"ok": false, "code": "...", "message": "..."}`. Asynchronous operations return `state` equal to `Complete`, `Failed`, or `Cancelled`. Progress text is localized; clients must use numeric fields and `state` for decisions. `total: 0` means an unknown total, not completion. `audio` events have a null ID and report playback state and time.

Only one processing operation runs at a time. While it is active, every command except `pause`, `resume`, `cancel`, `status`, and `shutdown` returns `busy`, including queries and audio commands. Pausing is cooperative: `pauseRequested` confirms the request, while `status.paused` or `progress.paused` confirms arrival at a checkpoint. A single operating-system file call may finish before the next checkpoint.

## Commands

| Command | Arguments and result |
| --- | --- |
| `sources` | Lists source adapters as `Id`, `Name`, `Input`. Bundled IDs: `itunes`, `single-folder`. |
| `formats` | Lists `Id`, `Label`, `Extension`, `Muxer`, `Options`. |
| `devices` | Lists audio devices as `Id`, `Name`; empty ID selects the Windows default device. |
| `network.status` | Lists remembered network-share outcomes for this process. |
| `network.reset` | Explicitly clears those outcomes, allowing a new connection attempt. |
| `configure` | Updates the session configuration described below. Does not modify GUI settings. |
| `load` | Required `path`; reads it with the configured source loader. Replaces loaded lists and clears selection on success. |
| `lists` | Returns `id`, `name`, `parentId`, `folder`, `smart`, `tracks`. Folder counts here are direct items, not aggregated descendants. |
| `tracks` | Optional `playlistId`, `offset` (0), `limit` (100, maximum 1000). Returns `total`, `offset`, `items`. Track properties include `PlaylistId`, `Order`, `Id`, `Title`, `Artist`, `Path`, `OriginalPath`, `Available`, `Seconds`, `Format`, `FileStatus`, `FileError`. |
| `select` | Optional `playlistIds`, `trackRefs`, or explicit `all: true`. Folder IDs include descendant playlists. A track reference is `{"playlistId":"...","order":1}`. With no selectors, retains the existing selection. Returns `selected` count. |
| `clearSelection` | Clears the selection. |
| `check` | Rechecks files and library filename candidates using current options. Returns `fileCheck`. |
| `issues` | Pages through the last file-check issues using `offset`, `limit` (maximum 1000). |
| `export` | Required absolute `destination`; optional `mode`, `target`, `options`, `extension`, `muxer`, `asciiNames`, plus the same selectors as `select`. Without selectors, uses the current selection. Groups selected rows into their original playlist folders. |
| `sync` | Required iTunes XML `path` and absolute `destination`. Extended hard-link synchronization; available only with the `itunes` loader. |
| `pause` | Requests a pause of the active processing operation. |
| `resume` | Resumes that operation. |
| `cancel` | `mode: "keep"` (default) immediately stops and keeps partial output; `mode: "rollback"` stops and restores items created by that operation. Both release a paused operation. |
| `rollback` | Restores the last export/sync operation created in this process. No previous-session journal or arbitrary path is accepted. |
| `status` | Returns `busy`, `paused`, `audioPosition`, `audioDuration`. |
| `audio.play` | Current selection or selectors; optional `mode`: `normal`, `loop`, `random`, `random-loop`. Unavailable tracks are excluded. |
| `audio.test` | Plays the bundled original test sound. |
| `audio.pause`, `audio.resume`, `audio.stop` | Controls audio playback. |
| `audio.seek` | Required `seconds`, from zero to the current track's XML/loader duration. Preserves paused state; unavailable when that duration is unknown or for the test sound. |
| `shutdown` | Stops audio and exits; an active processing operation is cancelled with `mode: "keep"` or `"rollback"`. |

`mode` for export is one of `Copy`, `Hardlink`, `Mp3`, `Aac`, `Flac`, `Alac`, `Wav`, `Opus`, `Vorbis`, `Custom`. `target` is `Generic`, `MusicBee`, `Foobar2000`, `Aimp`, or `Retone`. IDs and enum values should use the spellings shown here. Conversion options use the same allowlist as the GUI and are not shell commands. Source files, input paths and destination paths are supplied separately.

Each export creates a new `QitesXmlLoader-xxxxxxxx` child directory inside `destination`; its absolute path is returned as `result.data.output`. A partial rollback returns a failed result and retains the operation, so `rollback` can be retried after releasing locked files.

## Session configuration

```json
{"id":1,"command":"configure","args":{"SourceLoader":"itunes","MissingPolicy":"Stop","ResolveLibraryNames":true,"FFmpegPath":"C:\\Tools\\ffmpeg\\bin\\ffmpeg.exe","OutputDeviceId":"","Language":"en","CacheDirectory":"C:\\Work\\QitesCache"}}
```

Defaults: `SourceLoader: "itunes"`, `MissingPolicy: "Stop"`, `ResolveLibraryNames: false`, empty FFmpeg/device IDs, `Language: "en"`, and the user-local Qites cache directory. An empty FFmpeg path searches PATH. `CacheDirectory` must be absolute. Changing source adapters clears loaded data and selection. Changes to file-check settings require `check` or a new `load` to refresh the rows. Audio configuration applies to subsequent playback.

`AllowNetworkPaths` defaults to false and must be a JSON boolean. Enabled UNC shares are checked once per server/share and the outcome is retained across worker operations. Successful file metadata reads reuse the Windows connection; a failed initial share check or a detected connection failure prevents repeated per-track attempts. `network.reset` or a new process permits retry. This memory stores no credentials. Reject/approve decision modes override `MissingPolicy`, `ResolveLibraryNames`, and `AllowNetworkPaths` until `ErrorDecision` changes. Mapped drives and local links follow Windows configuration and are not a separate network sandbox.

`MissingPolicy: "Stop"` rejects an export before creating output when tracks cannot be accessed. `"Skip"` excludes inaccessible rows from both output files and playlists. If all rows are unavailable, no export output is created. File-check results contain row counts and unique-source-path counts, plus at most 20 inline issues; use `issues` for further pages. Types of issues: `Missing`, `Error`, `Ambiguous`, `Resolved`.

When `ResolveLibraryNames` is true, only paths registered in the loaded library's complete track catalog are considered. No directory traversal is performed by this recovery feature. All matching basenames, including extensions, are checked. Exactly one existing path is adopted even if several stale paths are registered. Two or more existing paths remain ambiguous. Candidate-check errors prevent an uncertain candidate from being treated as unique. Filename matching does not verify audio identity. The source XML is never rewritten.

Each request and result is local pipe traffic. Paths and titles in output may contain personal information. No network transport, authentication service, or automatic telemetry is provided.

## Python example

```python
import json
import subprocess

with subprocess.Popen(
    [r"C:\Apps\QitesXmlLoader\QitesXmlLoader.exe", "--pipe"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, encoding="utf-8", bufsize=1,
) as process:
    ready = json.loads(process.stdout.readline())
    assert ready["type"] == "ready"

    def call(request_id, command, args=None):
        process.stdin.write(json.dumps(
            {"id": request_id, "command": command, "args": args or {}},
            ensure_ascii=False,
        ) + "\n")
        process.stdin.flush()
        while line := process.stdout.readline():
            event = json.loads(line)
            if event["type"] == "progress":
                print(event["data"])
            if event["type"] == "result" and event["id"] == request_id:
                if not event["data"]["ok"]:
                    raise RuntimeError(event["data"])
                return event["data"].get("value", event["data"])
        raise RuntimeError(process.stderr.read())

    call(1, "configure", {
        "SourceLoader": "single-folder", "MissingPolicy": "Skip",
    })
    call(2, "load", {"path": r"C:\Music\Album"})
    call(3, "select", {"all": True})
    result = call(4, "export", {
        "destination": r"C:\Exports", "mode": "Copy", "target": "MusicBee",
    })
    print(result["output"])
    call(5, "shutdown")
    process.stdin.close()
    assert process.wait() == 0
```

For long-running integrations, continuously drain standard output and standard error and implement timeouts. Send control commands from a separate writer while the reader dispatches results by ID. Closing stdin normally lets an active operation finish before exit. Closing stdin while it is paused cancels it with partial output retained, so the process does not wait indefinitely for a resume command. EOF stops audio. Abrupt process termination does not perform rollback.
