# Media Downloader

A Windows command-line tool that scans a page URL and downloads discovered videos and images. Tool filenames, application messages, and documentation are in English. Downloaded content retains the original page or video title, including Chinese characters. Source metadata and operating-system error messages retain their original language.

## Quick start

Requires Windows 10/11 (x64) and Windows PowerShell 5.1 or later. No Python installation is required.

1. Clone this repository or extract the portable package.
2. For a source checkout, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\InstallDependencies.ps1`. This downloads yt-dlp and FFmpeg from their upstream GitHub releases. Portable packages already include these binaries.
3. Double-click `StartDownload.cmd`, paste a page URL, and press Enter.

The default output directory is `D:\MediaDownloads`. Use `-OutputDirectory` if the D: drive is unavailable. The content folder uses the original video, playlist, or page title without a timestamp suffix. Videos are saved directly inside that folder; images use an `Images` subfolder. The task also saves `scan.json` and `results.json` as applicable. Repeated runs reuse the title folder; run-specific diagnostic logs remain separate.

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

### Main video selection (1.2)

Automatic downloads use confirmed player sources, explicit page video metadata, direct media responses, or specialized site extractors. A single HTML video player is selected; an explicit main-player marker can distinguish it from other players. Alternative sources inside one player are treated as formats of one video, not separate downloads. Multiple indistinguishable players or conflicting metadata are reported as ambiguous.

Raw media links in scripts, recommendations, anchor tags, and hidden data are saved as `VideoCandidates` in `scan.json`; they are never used as automatic replacements for an unresolved main video. Generic extractor results are not trusted when no main player was confirmed. A failed main download does not trigger a download of unrelated candidates. Dedicated series adapters retain their episode-list behavior.

`VideoSelection` records the selection reason and player evidence. The error log records a selection summary and unresolved decisions. A download run with no confirmed main video exits with code 2, even if images were downloaded. Scan-only runs still produce a manifest without starting downloads.

This is conservative static-page selection, not browser network capture. JavaScript-only players and unsupported embedded players may remain unresolved; their candidate URLs are retained for diagnosis. Selecting a player identifies its declared source, not a guarantee about the contents of a remote stream.

- Videos: yt-dlp site extractors, direct media URLs, HLS/DASH, and supported playlists. An Ikanbot adapter selects one playback source to avoid duplicate episodes. It preserves the series title and normalizes original Chinese episode labels to two digits. Other extractors preserve individual video titles without appending IDs.
- Images: HTML image tags, common lazy-loading attributes, srcset variants, posters, Open Graph images, and explicit image links. Responses must have an image MIME type. Different srcset sizes are separate downloads.
- Content file and folder names preserve Unicode titles. Only characters invalid in Windows filenames are replaced; reserved names and overly long names may be adjusted. Source metadata in JSON manifests is preserved. Distinct videos with identical titles share a target filename, so use separate output roots if needed.
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

Run `tests\TestVideoSelection.ps1`, `tests\TestNaming.ps1`, and `tests\TestDiagnostics.ps1` with Windows PowerShell. `tests\TestMainVideoDownload.ps1` additionally requires installed binaries and uses a local HTTP fixture to verify that a main video downloads while recommendation URLs are never requested, and that an unresolved page fails explicitly.

Source files, documentation, and upstream license notices are tracked in Git. Downloaded media, runtime logs, archives, and third-party executable binaries are excluded. Run the dependency installer after cloning.

## Third-party software

- yt-dlp: https://github.com/yt-dlp/yt-dlp (see `yt-dlp-LICENSE.txt`).
- FFmpeg: https://ffmpeg.org/ and Windows builds at https://github.com/BtbN/FFmpeg-Builds (see `FFmpeg-LICENSE.txt`).

Bundled binaries retain their upstream licenses. The installer downloads the latest upstream builds, so binary versions can change independently of this repository.
