[CmdletBinding()]
param(
    [string]$Url,
    [string]$OutputDirectory = 'D:\MediaDownloads',
    [ValidateSet('all','video','image')][string]$Type = 'all',
    [switch]$ScanOnly,
    [string]$ResumeDirectory,
    [int]$MaxVideos = 0,
    [int]$MaxImages = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'error-logging.ps1')
. (Join-Path $PSScriptRoot 'video-selection.ps1')
Initialize-Diagnostics (Join-Path $PSScriptRoot 'logs')
trap {
    Write-Diagnostic -Stage 'fatal' -Message $_.Exception.Message -MediaUrl $Url -Record $_
    Write-Host "Run failed. Error log: $script:DiagnosticText"
    exit 1
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
$bin = Join-Path $PSScriptRoot 'bin'
$yt = Join-Path $bin 'yt-dlp.exe'
if (!$Url) { $Url = Read-Host 'Enter a page URL' }
$pageUri = $null
if (![Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$pageUri) -or $pageUri.Scheme -notin @('http','https')) { throw 'Enter a valid HTTP or HTTPS URL' }
if ($MaxVideos -lt 0 -or $MaxImages -lt 0) { throw 'Download limits cannot be negative' }
function SafeName([string]$name) {
    $name = [regex]::Replace($name, '[\x00-\x1f<>:"/\\|?*]', '_').Trim().TrimEnd('.')
    if (!$name) { $name = 'Untitled' }
    if ($name.Length -gt 90) { $name = $name.Substring(0,90) }
    if ($name -match '^(CON|PRN|AUX|NUL|COM\d|LPT\d)(\.|$)') { $name = '_' + $name }
    return $name
}
function ResolveMedia([string]$value) {
    if (!$value) { return $null }
    $value = [Net.WebUtility]::HtmlDecode($value.Trim()).Replace('\/', '/')
    try { $resolved = [Uri]::new($pageUri,$value); if ($resolved.Scheme -in @('http','https')) { return $resolved.AbsoluteUri } } catch {}
    return $null
}
function DirectVideoName([string]$Title,[string]$Label,[int]$Index,[int]$Count) {
    if ($Label -match '\u7b2c\s*(\d+)\s*\u96c6') {
        $number=[int]$Matches[1]
        $Label=([string][char]0x7b2c)+('{0:D2}' -f $number)+([string][char]0x96c6)
    } elseif (!$Label -and $Count -gt 1) { $Label='Video {0:D3}' -f $Index }
    $name=$Title; if($Label){$name=$Title+' '+$Label}
    return SafeName $name
}
$handler = New-Object Net.Http.HttpClientHandler
$handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
$client = New-Object Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromMinutes(5)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 MediaDownloader/1.0')
$client.DefaultRequestHeaders.Referrer = $pageUri
$warnings = New-Object 'Collections.Generic.List[string]'
$videos = New-Object 'Collections.Generic.List[object]'
$images = New-Object 'Collections.Generic.List[object]'
$seenVideos = New-Object 'Collections.Generic.HashSet[string]'
$seenImages = New-Object 'Collections.Generic.HashSet[string]'
function AddMedia([string]$kind,[string]$link,[string]$name) {
    $link = ResolveMedia $link
    if (!$link) { return }
    $entry = [pscustomobject]@{Url=$link;Name=$name}
    if ($kind -eq 'video') { if ($seenVideos.Add($link)) { $videos.Add($entry) } }
    else { if ($seenImages.Add($link)) { $images.Add($entry) } }
}
Write-Host 'Scanning page...'
$html = ''; $title = $pageUri.Host; $contentType = ''
try {
    $response = $client.GetAsync($pageUri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null
    $contentType=$response.Content.Headers.ContentType.MediaType
    if($contentType -like 'image/*'){if($Type -ne 'video'){AddMedia image $Url ''}}
    elseif($contentType -like 'video/*' -or $contentType -eq 'application/octet-stream'){if($Type -ne 'image'){AddMedia video $Url ''}}
    else { $html = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    $response.Dispose()
    $match = [regex]::Match($html, '(?is)<title[^>]*>(.*?)</title>')
    if ($match.Success) { $title = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value).Trim() }
} catch { $warnings.Add('Page fetch failed: ' + $_.Exception.Message); Write-Diagnostic -Stage 'page-fetch' -Message $_.Exception.Message -MediaUrl $Url -Record $_ }
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
# Collect static tags, lazy images, srcset, Open Graph, and explicit media URLs.
foreach ($tagMatch in [regex]::Matches($html, '(?is)<(img|video|source|a|meta)\b[^>]*>')) {
    $tag = $tagMatch.Value; $tagName = $tagMatch.Groups[1].Value.ToLowerInvariant()
    $attrs = @{}
    foreach ($a in [regex]::Matches($tag, '(?is)([\w:-]+)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))')) {
        $value = $a.Groups[2].Value; if (!$a.Groups[2].Success) { $value = $a.Groups[3].Value }; if (!$a.Groups[3].Success -and !$a.Groups[2].Success) { $value = $a.Groups[4].Value }
        $attrs[$a.Groups[1].Value.ToLowerInvariant()] = $value
    }
    if ($Type -ne 'video') {
        if ($tagName -eq 'img') {
            foreach ($key in @('src','data-src','data-original','data-lazy-src')) { AddMedia image $attrs[$key] '' }
        }
        if ($tagName -in @('img','source') -and $attrs['srcset']) { foreach ($item in ($attrs['srcset'] -split ',')) { AddMedia image (($item.Trim() -split '\s+')[0]) '' } }
        if ($attrs['poster']) { AddMedia image $attrs['poster'] '' }
        if ($tagName -eq 'meta' -and ($attrs['property'] -eq 'og:image' -or $attrs['name'] -eq 'twitter:image')) { AddMedia image $attrs['content'] '' }
    }
    foreach ($key in @('src','href','data-src','content')) {
        $link = $attrs[$key]
        if ($Type -ne 'image' -and ($link -match '(?i)\.(mp4|m3u8|mpd|webm|mov|mkv)(?:[?#]|$)' -or ($tagName -eq 'video' -and $key -eq 'src'))) { AddMedia video $link '' }
        if ($Type -ne 'video' -and $link -match '(?i)\.(jpe?g|png|webp|gif|avif|bmp|svg)(?:[?#]|$)') { AddMedia image $link '' }
    }
}
$unescaped = $html.Replace('\/','/').Replace('\u0026','&')
foreach ($m in [regex]::Matches($unescaped, '(?i)https?://[^\s"''<>\\]+?\.(mp4|m3u8|mpd|webm|mov|mkv|jpe?g|png|webp|gif|avif|bmp|svg)(?:\?[^\s"''<>\\]*)?')) {
    if ($m.Groups[1].Value -match '^(mp4|m3u8|mpd|webm|mov|mkv)$') { if ($Type -ne 'image') { AddMedia video $m.Value '' } }
    elseif ($Type -ne 'video') { AddMedia image $m.Value '' }
}
$videoCandidates=@($videos.ToArray())
$videos.Clear(); $seenVideos.Clear()
$selection=Get-MainVideoSelection -Html $html -PageUri $pageUri -ContentType $contentType
# Ikanbot adapter: use the public player API and select one source to avoid duplicate episodes.
$siteAdapted = $false
if ($Type -ne 'image' -and $pageUri.Host -match '(^|\.)ikanbot\.com$') {
    try {
        $id = [regex]::Match($html,'id="current_id" value="([^"]+)"').Groups[1].Value
        $token = [regex]::Match($html,'id="e_token" value="([^"]+)"').Groups[1].Value
        $mtype = [regex]::Match($html,'id="mtype" value="([^"]+)"').Groups[1].Value
        $tk = ''; foreach ($digit in $id.Substring($id.Length-4).ToCharArray()) { $n=([int]::Parse([string]$digit)%3)+1; $tk+=$token.Substring($n,8); $token=$token.Substring($n+8) }
        $api = [Uri]::new($pageUri, '/api/getResN?videoId=' + $id + '&mtype=' + $mtype + '&token=' + $tk)
        $data = $client.GetStringAsync($api).GetAwaiter().GetResult() | ConvertFrom-Json
        foreach ($line in $data.data.list) {
            foreach ($source in ($line.resData | ConvertFrom-Json)) {
                foreach ($entry in ($source.url -split '#')) { $parts=$entry -split '\$'; if($parts.Count -ge 2){ AddMedia video $parts[1] $parts[0] } }
                if ($videos.Count) { break }
            }
            if ($videos.Count) { break }
        }
        $siteAdapted = $videos.Count -gt 0
        $h1 = [regex]::Match($html,'(?is)<h1[^>]*>(.*?)</h1>'); if($h1.Success){ $title=[Net.WebUtility]::HtmlDecode($h1.Groups[1].Value).Trim() }
    } catch { $warnings.Add('Site adapter failed: ' + $_.Exception.Message); Write-Diagnostic -Stage 'site-adapter' -Message $_.Exception.Message -MediaUrl $Url -Record $_ }
}
if(!$siteAdapted -and $Type -ne 'image'){
    foreach($item in $selection.Selected){AddMedia video $item.Url $item.Name}
}
$extractor = $null
$extractorLog = $null
if ($Type -ne 'image' -and !$siteAdapted -and $videos.Count -eq 0) {
    if (!(Test-Path -LiteralPath $yt)) { throw 'Missing bin\yt-dlp.exe' }
    Write-Host 'Running the general video extractor...'
    $extractorLog = Join-Path (Join-Path $PSScriptRoot 'logs') ($script:DiagnosticRunId+'.extractor.log')
    $savedPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
    $raw = & $yt --dump-single-json --skip-download --flat-playlist --socket-timeout 15 --retries 1 --extractor-retries 1 --no-warnings -- $Url 2> $extractorLog
    $extractorExit=$LASTEXITCODE; $ErrorActionPreference=$savedPreference
    if(Test-Path -LiteralPath $extractorLog){
        $extractorText=Get-Content -LiteralPath $extractorLog -Raw
        (Protect-LogText $extractorText) | Set-Content -LiteralPath $extractorLog -Encoding UTF8
        if($extractorExit -ne 0){Write-Diagnostic -Stage 'video-extract' -Message $extractorText -MediaUrl $Url -ExitCode $extractorExit}
    }
    if ($extractorExit -eq 0 -and $raw) {
        try { $extractor = ($raw -join "`n") | ConvertFrom-Json } catch { $warnings.Add('The video extractor returned invalid JSON'); Write-Diagnostic -Stage 'extractor-json' -Message $_.Exception.Message -MediaUrl $Url -Record $_ }
    } else { $warnings.Add('The extractor failed. Unconfirmed candidate URLs will not be downloaded. See extractor.log.') }
    if($extractor -and !(Test-SpecializedExtractor $extractor)){
        $extractor=$null
        $warnings.Add('Generic extractor results were rejected because no main player was confirmed.')
    }
}
$extractorCount = 0
if ($extractor) {
    $entries = @($extractor)
    if ($extractor.entries) { $entries = @($extractor.entries | Where-Object { $null -ne $_ }) }
    $extractorCount = $entries.Count
}
$videoCount = $videos.Count; if($extractor){$videoCount=$extractorCount}
if($siteAdapted){$selection.Reason='Dedicated site adapter selected the series playback source'}
elseif($extractor){$selection.Reason='Specialized site extractor: '+$extractor.extractor_key}
Write-Diagnostic -Stage 'video-selection-summary' -Severity Info -Message ($selection.Reason+'; selected='+$videoCount+'; unverified candidates='+$videoCandidates.Count) -MediaUrl $Url
if ($extractor) {
    if ($extractor.playlist_title) { $title=$extractor.playlist_title }
    elseif ($extractor.title) { $title=$extractor.title }
}
$folder = Join-Path $OutputDirectory (SafeName $title)
if ($ResumeDirectory) { $folder = [IO.Path]::GetFullPath($ResumeDirectory) }
[IO.Directory]::CreateDirectory($folder) | Out-Null
$log = Join-Path $folder 'download.log'
if ($extractorLog -and (Test-Path -LiteralPath $extractorLog)) {
    Copy-Item -LiteralPath $extractorLog -Destination (Join-Path $folder 'extractor.log') -Force
}
$manifestPath = Join-Path $folder 'scan.json'
[pscustomobject]@{Page=$Url;Title=$title;Time=(Get-Date -Format o);Videos=@($videos.ToArray());VideoCandidates=$videoCandidates;VideoSelection=$selection;SiteAdapterSelected=$siteAdapted;Images=@($images.ToArray());ExtractorVideoCount=$extractorCount;Warnings=@($warnings.ToArray())} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host ("Scan result: {0} videos, {1} images" -f $videoCount,$images.Count)
$unresolvedVideo=$Type -ne 'image' -and $videoCount -eq 0
if($unresolvedVideo){
    Write-Warning 'Main video not identified. No unconfirmed video URLs will be downloaded.'
    Write-Diagnostic -Stage 'main-video-selection' -Message $selection.Reason -MediaUrl $Url
}
if ($ScanOnly) { Write-Host "Scan manifest: $manifestPath"; $client.Dispose(); return }
$results = New-Object 'Collections.Generic.List[object]'
if($unresolvedVideo){$results.Add([pscustomobject]@{Kind='video';Url=$Url;Success=$false;Stage='main-video-selection';Error=$selection.Reason})}
function DownloadVideo([string]$link,[string]$template) {
    $archiveDir = Join-Path $OutputDirectory '.archives'; [IO.Directory]::CreateDirectory($archiveDir) | Out-Null
    $digest = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($link)))).Replace('-','') } finally { $digest.Dispose() }
    $argsList = @('--newline','--no-warnings','--socket-timeout','30','--retries','5','--fragment-retries','5','--abort-on-unavailable-fragments','--concurrent-fragments','6','--continue','--windows-filenames','--ffmpeg-location',$bin,'--merge-output-format','mp4','--remux-video','mp4','--fixup','force','--download-archive',(Join-Path $archiveDir ($key+'.txt')),'--referer',$Url,'-o',$template)
    if($MaxVideos -gt 0){$argsList += @('--playlist-end', "$MaxVideos")}
    $savedPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
    & $yt @argsList -- $link 2>&1 | ForEach-Object {
        $text=Protect-LogText "$_"; Write-Host $text; $text | Add-Content -LiteralPath $log -Encoding UTF8
        if($text -match '(?i)ERROR:'){Write-Diagnostic -Stage 'video-download' -Message $text -MediaUrl $link}
        elseif($text -match '(?i)WARNING:|Retrying|retrying fragment'){Write-Diagnostic -Stage 'video-retry' -Severity Warning -Message $text -MediaUrl $link}
    }
    $ok = $LASTEXITCODE -eq 0; $ErrorActionPreference=$savedPreference
    if(!$ok){Write-Diagnostic -Stage 'video-exit' -Message 'Video download failed. See download.log for details.' -MediaUrl $link -ExitCode $LASTEXITCODE}
    $results.Add([pscustomobject]@{Kind='video';Url=$link;Success=$ok})
}
if ($Type -ne 'image') {
    $videoDir = $folder
    if ($extractor) {
        $template = Join-Path $videoDir '%(title)s.%(ext)s'
        DownloadVideo $Url $template
    } else {
        $i=0; foreach($v in $videos){ $i++; if($MaxVideos -gt 0 -and $i -gt $MaxVideos){break}
            $mediaName=DirectVideoName $title $v.Name $i $videos.Count
            DownloadVideo $v.Url (Join-Path $videoDir ($mediaName + '.%(ext)s'))
        }
    }
}
if ($Type -ne 'video') {
    $imageDir=Join-Path $folder 'Images'; [IO.Directory]::CreateDirectory($imageDir) | Out-Null
    $i=0
    foreach($img in $images){ $i++; if($MaxImages -gt 0 -and $i -gt $MaxImages){break}
        $temp=$null; $response=$null; $stream=$null; $file=$null
        try {
            $response=$client.GetAsync($img.Url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult(); $response.EnsureSuccessStatusCode() | Out-Null
            $mime=$response.Content.Headers.ContentType.MediaType
            if($mime -notlike 'image/*'){throw "Response is not an image: $mime"}
            $ext=switch($mime){'image/jpeg'{'.jpg'} 'image/png'{'.png'} 'image/webp'{'.webp'} 'image/gif'{'.gif'} 'image/avif'{'.avif'} 'image/svg+xml'{'.svg'} 'image/bmp'{'.bmp'} default{'.img'}}
            $sha=[Security.Cryptography.SHA256]::Create(); try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($img.Url)))).Replace('-','').Substring(0,12)}finally{$sha.Dispose()}
            $path=Join-Path $imageDir ('Image{0:D3}_{1}{2}' -f $i,$hash,$ext); $temp=$path+'.part'
            $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult(); $file=[IO.File]::Create($temp); $stream.CopyTo($file); $file.Dispose(); $file=$null
            if((Get-Item -LiteralPath $temp).Length -eq 0){throw 'The image is empty'}
            Move-Item -LiteralPath $temp -Destination $path -Force
            $results.Add([pscustomobject]@{Kind='image';Url=$img.Url;Success=$true;Path=$path}); Write-Host "Image saved: $path"
        } catch { Write-Diagnostic -Stage 'image-download' -Message $_.Exception.Message -MediaUrl $img.Url -Record $_; $results.Add([pscustomobject]@{Kind='image';Url=$img.Url;Success=$false;Error=$_.Exception.Message}); Write-Warning $_.Exception.Message }
        finally {if($file){$file.Dispose()}; if($stream){$stream.Dispose()}; if($response){$response.Dispose()}}
    }
}
$client.Dispose()
$results.ToArray() | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $folder 'results.json') -Encoding UTF8
$failed=@($results | Where-Object {!$_.Success}).Count
Write-Host "Run finished. Failed tasks: $failed; output folder: $folder"
if($videoCount -eq 0 -and $images.Count -eq 0){Write-Warning 'No media found. This page may require login, browser scripting, or an unsupported site adapter.'; Write-Diagnostic -Stage 'empty-scan' -Severity Warning -Message 'No media found' -MediaUrl $Url}
Write-Host "Diagnostic log: $script:DiagnosticText"
if($failed -gt 0){exit 2}
