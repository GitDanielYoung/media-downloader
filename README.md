# Media Downloader

A Windows command-line tool that scans a page URL and downloads discovered videos and images. All application messages, documentation, and generated filename labels are in English. Source page metadata and operating-system error messages retain their original language.

## Quick start

Requires Windows 10/11 (x64) and Windows PowerShell 5.1 or later. No Python installation is required.

1. Clone this repository or extract the portable package.
2. For a source checkout, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\InstallDependencies.ps1`. This downloads yt-dlp and FFmpeg from their upstream GitHub releases. Portable packages already include these binaries.
3. Double-click `StartDownload.cmd`, paste a page URL, and press Enter.

The default output directory is `D:\MediaDownloads`. Use `-OutputDirectory` if the D: drive is unavailable. Each run creates a separate task folder containing `Videos`, `Images`, `scan.json`, and `results.json` as applicable.

## Commands

```powershell
.\media-downloader.ps1 -Url 'https://example.com/page'
.\media-downloader.ps1 -Url 'https://example.com/page' -ScanOnly
.\media-downloader.ps1 -Url 'https://example.com/page' -Type image
.\media-downloader.ps1 -Url 'https://example.com/page' -Type video -OutputDirectory 'C:\MediaDownloads'
.\media-downloader.ps1 -Url 'https://example.com/page' -MaxVideos 2 -MaxImages 10
.\media-downloader.ps1 -Url 'https://example.com/page' -ResumeDirectory 'D:\MediaDownloads\previous-task'
```

Types: `all` (default), `video`, `image`. A limit of zero means unlimited. `-ScanOnly` saves a discovery manifest without downloading media. To resume a video, reuse the original URL, options, and task directory with `-ResumeDirectory`.

## Supported behavior

- Videos: yt-dlp site extractors, direct media URLs, HLS/DASH, and supported playlists. An Ikanbot adapter selects one playback source to avoid duplicate episodes. Episode labels use `Episode 01`.
- Images: HTML image tags, common lazy-loading attributes, srcset variants, posters, Open Graph images, and explicit image links. Responses must have an image MIME type. Different srcset sizes are separate downloads.
- Generated file and folder names use ASCII. Page titles without usable ASCII characters use a fallback name. Source metadata in JSON manifests is preserved.
- Video downloads retry and resume through yt-dlp; missing fragments abort the affected download. Image failures do not stop subsequent images.
- `.archives` under the output root records completed videos separately by source URL. Repeated runs skip recorded videos. Use another output root to download them again.
- Playlist results are recorded as one task. Consult `download.log` for individual download progress.
- The tool scans one page, not an entire website. Browser-only dynamic content, login requirements, CAPTCHA, and DRM may prevent discovery or downloading. It does not bypass these restrictions.
- Update yt-dlp with `bin\yt-dlp.exe -U`.

## Error logs

Each run creates a unique pair under the tool's `logs` directory:

- `timestamp_runid.errors.log`: readable diagnostic messages.
- `timestamp_runid.errors.jsonl`: structured events for analysis.

Events include timestamps, run ID, environment details, failure stage, resource URL, exception chains, script location, and video process exit codes when available. Fetch failures, adapter failures, extraction failures, video retries, image failures, and unhandled exceptions are recorded. The console displays the log location. Exit code 1 indicates an unhandled error; exit code 2 indicates a failed download task.

Logs remain local and are never automatically uploaded. Error logs, `download.log`, and `extractor.log` redact URL credentials, query strings, fragments, and common credential fields. URL paths and local paths can still contain personal information. Review logs before sharing. `scan.json` and `results.json` retain original URLs and may contain signed links; do not publish them without review.

## Development

Source files, documentation, and upstream license notices are tracked in Git. Downloaded media, runtime logs, archives, and third-party executable binaries are excluded. Run the dependency installer after cloning.

## Third-party software

- yt-dlp: https://github.com/yt-dlp/yt-dlp (see `yt-dlp-LICENSE.txt`).
- FFmpeg: https://ffmpeg.org/ and Windows builds at https://github.com/BtbN/FFmpeg-Builds (see `FFmpeg-LICENSE.txt`).

Bundled binaries retain their upstream licenses. The installer downloads the latest upstream builds, so binary versions can change independently of this repository.