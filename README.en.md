# Qites xml loader

[日本語](README.md) / [English specifications](README.en.md)

Windows x64 application for loading iTunes library XML, previewing local audio and exporting playlist files. Version: 0.9.

## Requirements and installation

- Windows 10 or 11 x64.
- Windows PowerShell 5.1 and .NET Framework 4.8.
- Optional external FFmpeg executable for conversion and FFmpeg-based decoding.

Run `QitesXmlLoader-Setup-0.9.exe`, then launch Qites xml loader from the Start menu. The portable ZIP provides `QitesXmlLoader.exe`. A custom installation directory must be new or empty:

```powershell
.\QitesXmlLoader-Setup-0.9.exe --target "D:\Apps\QitesXmlLoader"
```

The installer does not remove earlier installations. FFmpeg is not bundled or downloaded. Configure an actual `ffmpeg.exe`, its `bin` directory, or an installation root containing `bin/ffmpeg.exe`. An empty setting searches PATH.

## Source adapters

| Adapter ID | Input | Behavior |
| --- | --- | --- |
| `itunes` | Library XML | Default. Reads saved track and playlist records, including folder hierarchy and smart-playlist snapshots. No rule evaluation, COM access, application launch or library write-back. |
| `single-folder` | Directory | Sample. Enumerates supported audio files directly inside one folder, sorts by filename and returns one playlist. No recursion or artist/album tag extraction. Duration is obtained for WAV and selected Windows-supported formats; otherwise it is zero. |

Additional adapters use a JSON manifest and PowerShell entry script in `loaders/`. Adapter scripts are trusted executable extensions, not data-only configuration. Normal adapters return a `Library` with track and playlist dictionaries. The default adapter delegates to the iTunes XML/cache implementation. See [adapter contract](docs/LOADERS.md).

## Selection and playback

- Hierarchical playlist tree with separate normal, smart and folder labels.
- Folder selection displays descendant playlist rows; parent checkboxes cascade export selection.
- Ctrl, Shift and drag selection, retained across playlists. Right-click can add an entire playlist or folder subtree.
- A row is identified by its playlist and original position. Identical audio in different rows remains distinct.
- Playback source: selected tracks or the displayed playlist/folder. Order: normal, loop, random, random loop.
- Output-device selection and persistence. A disconnected saved device falls back to the Windows default, with status text.
- Seek bar, track elapsed/duration, and position/total in the visible playlist. Narrow layouts retain the seek bar and elapsed time. Playlist position uses original XML order, not accumulated loop time.
- Device changes during GUI playback restart the current track. Native Windows-supported playback and the original test sound do not require FFmpeg.

## File availability

The GUI provides `Stop` and `Skip` policies. Stop prevents export if selected rows are inaccessible. Skip excludes inaccessible rows from audio output and playlist files. An all-unavailable selection creates no export output. Loading and browsing remain available regardless of the export policy.

Optional filename recovery checks only paths registered in the complete loaded track catalog. It does not search directories. All matching basenames, including extensions, are checked. Exactly one existing path is adopted; two or more existing paths remain unresolved. Candidate access errors prevent an uncertain uniqueness decision. Multiple stale registrations do not prevent adopting one existing candidate. Audio content identity is not verified by filename matching. Source XML remains unchanged.

The GUI displays counts for missing rows, check errors, ambiguous candidates and relocated references, with separate unique-source-path counts. Details are recorded in `last-file-check.json` under diagnostic logs.

One GUI attempt retains one confirmation decision from preflight through export; subsequent confirmation defaults use the previous choice. UNC network paths require explicit opt-in. Share-access results are cached by server/share for the process lifetime; a failed share is not retried for each track. Credentials are not stored. Mapped drives and local filesystem links also follow Windows configuration. XML nesting is limited to 128 reader levels.

## Export

| Mode | Encoder/container |
| --- | --- |
| Copy | Original files; no FFmpeg required |
| Hardlink | Same-volume hard links; no FFmpeg required |
| Mp3 | MP3 / libmp3lame |
| Aac | AAC / M4A |
| Flac | FLAC |
| Alac | ALAC / M4A |
| Wav | PCM WAV |
| Opus | Opus |
| Vorbis | Ogg Vorbis |
| Custom | Configured extension, allowlisted container and output options |

MusicBee, foobar2000 and AIMP targets produce audio folders and relative M3U8/M3U playlists. Named-target output includes a combined `selection.m3u8`, a UTF-8 BOM `selection.m3u`, per-playlist lists and import instructions. Files and lists must move together. No target application is launched or modified.

The reTONE target produces a `Music` directory with numbered filenames such as `0001-normalized-title.ext`. Unicode titles are retained after filename normalization. An optional ASCII compatibility setting encodes non-ASCII title characters as alphanumeric identifiers. reTONE does not import external playlists; its M3U8 output is an order reference. Filename numbering only controls order where the target uses filename sorting. Target-player and Android-device imports have not been verified.

Extended hard-link synchronization is specific to iTunes XML. It retains prior links, adds current versioned M3U8 files, and reports residual links. Hard-linked audio must not be edited because the source and link share content. Cross-volume transfer uses ordinary file copies.

Successfully completed hard-link operations receive an interactive unlink BAT for newly created links and an identity manifest. It checks the original export directory, source/output identities, link counts and path boundaries, then requires `UNLINK` confirmation. It does not remove source paths or clear shared file attributes. Concurrent external mutation and malicious modification of the helper are outside its guarantees. Removal by this helper has not been executed in development; preview and rejection paths were tested. See [unlink specification](docs/UNLINK.md).

## Progress, cancellation and cache

Long operations report stages, counts and sizes. Pause and cancellation are cooperative at checkpoints. Immediate cancellation retains partial output. Rollback cancellation removes only items newly created by that operation, after file-identity checks. Existing sources and links are excluded. Replaced paths and nonempty directories are retained and reported. Crash recovery is not implemented.

The iTunes loader caches parsed records, checks the complete XML hash and reuses records whose subtree hashes are unchanged. It still reads the XML snapshot to verify updates; this is not a byte-range-only XML delta reader. Generic folder-adapter caching is not implemented.

## JSON Lines command mode

`QitesXmlLoader.exe --pipe` accepts UTF-8 JSON Lines through stdin and emits JSON Lines through stdout. No GUI or startup sound is created. Commands cover source/configuration queries, loading, selection, file checking, export, synchronization, progress control, rollback and audio playback. Session configuration is separate from saved GUI settings.

```json
{"id":1,"command":"configure","args":{"SourceLoader":"single-folder","MissingPolicy":"Skip"}}
{"id":2,"command":"load","args":{"path":"C:\\Music\\Album"}}
{"id":3,"command":"select","args":{"all":true}}
{"id":4,"command":"export","args":{"destination":"C:\\Exports","mode":"Copy","target":"MusicBee"}}
```

Wait for each final `result` before sending the next processing command. Control commands remain available during processing. See [protocol v1 and Python example](docs/PIPE-PROTOCOL.md) for schemas, limits, EOF behavior, cancellation and audio commands.

`--pipe --ignore-errors` selects negative confirmation decisions and skips unresolved rows. `--pipe --approve-errors` approves supported relocation and network access, while still skipping unavailable or ambiguous rows. Folder drop examples are included in `examples/` and use copy output through the pipe interface; no Python installation is required for those BAT samples.

## Localization and data storage

GUI languages: Japanese and English. Labels and font definitions are in `i18n/ja.json` and `i18n/en.json`. UI defaults are Yu Gothic UI for Japanese and Segoe UI for English; the code field uses Consolas. Missing, empty or unavailable font settings fall back to the Windows system message font. Font files are not distributed.

GUI settings, cache and diagnostic logs use the user's LocalAppData `QitesXmlLoader` directory. Logs and protocol responses can contain local paths and track titles. There is no automatic telemetry or log upload.

## Build and test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test.ps1 -NoAudio
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-FileCheck.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Sources.ps1
python .\tests\test_pipe.py
```

Build restores NAudio 2.2.1 packages from official NuGet endpoints and verifies pinned SHA256 hashes. It does not fetch FFmpeg. `Test.ps1 -FFmpegPath ...` adds external conversion tests. Omitting `-NoAudio` enables audio-device tests. `test_pipe.py --audio` enables protocol audio tests. Fixtures are synthetic.

Artifacts are written to `dist/`. Source publication uses an explicit whitelist to exclude caches, settings, logs, dependency DLLs and earlier binaries. See [publication procedure](docs/PUBLISH.md) and [release notes](docs/RELEASE_NOTES.md).

## Licenses and trademarks

Application code and original assets: Copyright (c) 2026 okdk, [MIT](LICENSE). NAudio: MIT, with its original notice included. FFmpeg is external and retains its own build-specific license terms. See [third-party notices](THIRD-PARTY.md) and [rights notice](NOTICE.md).

iTunes and Apple are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This is an independent, unofficial application and is not authorized, sponsored or approved by Apple Inc. It is not an official OpenAI product. Audio content remains subject to its respective rights holders' terms.
