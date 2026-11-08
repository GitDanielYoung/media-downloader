$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$tool=Join-Path $base 'media-downloader.ps1'
$logs=Join-Path (Split-Path $tool) 'logs'
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Url 'https://user:PRIVATEPASSWORD@example.com/test?token=PRIVATEQUERY#PRIVATEFRAGMENT' -MaxVideos -1
if($LASTEXITCODE -ne 1){throw 'Fatal exit status missing'}
$file=Get-ChildItem $logs -Filter '*.jsonl' | Sort-Object LastWriteTime | Select-Object -Last 1
$text=Get-Content $file.FullName -Raw
if($text -match 'PRIVATEPASSWORD|PRIVATEQUERY|PRIVATEFRAGMENT'){throw 'Secrets leaked'}
$events=@(Get-Content $file.FullName | ForEach-Object {$_ | ConvertFrom-Json})
if(!($events | Where-Object {$_.Stage -eq 'fatal' -and $_.Exceptions.Count -gt 0})){throw 'Fatal detail missing'}
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Url 'http://127.0.0.1:1/no-page' -Type image -ScanOnly -OutputDirectory (Join-Path ([IO.Path]::GetTempPath()) 'MediaDownloader-LoggingTest')
$file=Get-ChildItem $logs -Filter '*.jsonl' | Sort-Object LastWriteTime | Select-Object -Last 1
$events=@(Get-Content $file.FullName | ForEach-Object {$_ | ConvertFrom-Json})
if(!($events | Where-Object Stage -eq 'page-fetch')){throw 'Fetch detail missing'}
. (Join-Path (Split-Path $tool) 'error-logging.ps1')
Initialize-Diagnostics (Join-Path ([IO.Path]::GetTempPath()) 'MediaDownloader-LoggerUnitTest')
$clean=Protect-LogText 'ERROR https://user:PRIVATEPASSWORD@example.org/video?sign=PRIVATEQUERY#PRIVATEFRAGMENT Cookie: PRIVATECOOKIE'
if($clean -match 'PRIVATEPASSWORD|PRIVATEQUERY|PRIVATEFRAGMENT|PRIVATECOOKIE'){throw 'Redaction failed'}
Write-Diagnostic -Stage video-exit -Message 'Failed' -ExitCode 2
$entry=Get-Content $script:DiagnosticJson -Tail 1 | ConvertFrom-Json
if($entry.ExitCode -ne 2){throw 'Exit code missing'}
'PASS: fatal errors, fetch failures, exception chains, JSONL parsing, credential/query/fragment/cookie redaction, exit codes'
