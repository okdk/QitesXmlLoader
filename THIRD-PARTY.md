# Third-party components and notices

## NAudio 2.2.1

NAudio.Core and NAudio.Wasapi are distributed under the MIT license.
Copyright (c) 2020 Mark Heath.
The original license is included in `src/lib/NAudio-LICENSE.txt` in source distributions and `lib/NAudio-LICENSE.txt` in binary distributions. Its complete notice and permission terms are preserved there.

- Source: https://github.com/naudio/NAudio/tree/v2.2.1
- Packages: https://www.nuget.org/packages/NAudio.Core/2.2.1 and https://www.nuget.org/packages/NAudio.Wasapi/2.2.1
- Package files are downloaded from official NuGet endpoints and SHA256-checked by `scripts/Restore-Dependencies.ps1`.

## FFmpeg: external, not bundled

FFmpeg is not included in this repository's application ZIP or installer. Install a build separately and choose its `ffmpeg.exe` or `bin` directory in the app. FFmpeg runs as a separate process; no FFmpeg libraries are linked into this application.

FFmpeg is a trademark of Fabrice Bellard. FFmpeg builds carry their own LGPL/GPL license terms, depending on the build configuration. This application's license does not replace those terms. Anyone who later redistributes an FFmpeg build must check that build's redistribution and corresponding-source requirements.

- Project and downloads: https://ffmpeg.org/download.html
- License information: https://ffmpeg.org/legal.html
- Windows build provider: https://www.gyan.dev/ffmpeg/builds/

## Product names and content

iTunes and Apple are trademarks of Apple Inc., registered in the U.S. and other countries and regions. Qites xml loader is an independent, unofficial application and is not authorized, sponsored or approved by Apple Inc. It is not an official OpenAI application.

No Apple logo, iTunes icon, Apple executable, music recording, album artwork, Microsoft startup recording or font file is bundled. See `NOTICE.md` for the Japanese notice.
