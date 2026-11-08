[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$bin=Join-Path $PSScriptRoot 'bin'
[IO.Directory]::CreateDirectory($bin) | Out-Null
$temp=Join-Path ([IO.Path]::GetTempPath()) ('MediaDownloader-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
Write-Host 'Downloading yt-dlp and FFmpeg from their upstream GitHub releases...'
try {
    Invoke-WebRequest -UseBasicParsing 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile (Join-Path $bin 'yt-dlp.exe')
    $archive=Join-Path $temp 'ffmpeg.zip'
    Invoke-WebRequest -UseBasicParsing 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $temp
    foreach($name in @('ffmpeg.exe','ffprobe.exe')){
        $file=Get-ChildItem -LiteralPath $temp -Recurse -File -Filter $name | Select-Object -First 1
        if(!$file){throw "Missing dependency in archive: $name"}
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $bin $name) -Force
    }
    Write-Host 'Dependencies installed. Run StartDownload.cmd.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\MediaDownloader-'
    if($resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
