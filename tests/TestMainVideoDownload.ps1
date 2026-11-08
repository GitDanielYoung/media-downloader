$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('MainVideoTest-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$clip=Join-Path $temp 'main.mp4'
& (Join-Path $root 'bin\ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i color=size=64x64:rate=10 -t 1 -c:v libx264 -y $clip
if($LASTEXITCODE -ne 0){throw 'Could not create test clip'}
$probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
$requestLog=Join-Path $temp 'requests.txt'
$job=Start-Job -ArgumentList $port,$clip,$requestLog -ScriptBlock {
    param($port,$clip,$requestLog)
    $listener=New-Object Net.HttpListener;$listener.Prefixes.Add("http://127.0.0.1:$port/");$listener.Start()
    try{while($true){
        $ctx=$listener.GetContext();$path=$ctx.Request.Url.AbsolutePath;$path | Add-Content $requestLog
        if($path -eq '/stop'){$ctx.Response.Close();break}
        $type='text/html; charset=utf-8'
        $body=[Text.Encoding]::UTF8.GetBytes('<html><title>Original Title</title><video src="/main.mp4"></video><a href="/other.mp4">Recommendation</a><script>var recommendation="http://127.0.0.1:'+ $port +'/other.mp4"</script></html>')
        if($path -eq '/unresolved'){$body=[Text.Encoding]::UTF8.GetBytes('<html><title>Unresolved</title><script>var recommendation="http://127.0.0.1:'+$port+'/other.mp4"</script></html>')}
        if($path -eq '/main.mp4'){$type='video/mp4';$body=[IO.File]::ReadAllBytes($clip)}
        $ctx.Response.ContentType=$type;$ctx.Response.ContentLength64=$body.Length
        try{$ctx.Response.OutputStream.Write($body,0,$body.Length)}catch{}
        $ctx.Response.Close()
    }}finally{$listener.Stop()}
}
try{
    Start-Sleep -Seconds 2
    $output=Join-Path $temp 'downloads';$tool=Join-Path $root 'media-downloader.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Url "http://127.0.0.1:$port/page" -Type video -OutputDirectory $output
    if($LASTEXITCODE -ne 0){throw 'Main video download failed'}
    $file=Get-Item -LiteralPath (Join-Path $output 'Original Title\Original Title.mp4')
    if($file.Length -ne (Get-Item $clip).Length){throw 'Main video bytes differ'}
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Url "http://127.0.0.1:$port/unresolved" -Type video -OutputDirectory $output
    if($LASTEXITCODE -ne 2){throw 'Unresolved video must fail explicitly'}
    if((Get-Content $requestLog) -contains '/other.mp4'){throw 'A recommendation was requested'}
    $manifest=Get-Content (Join-Path $output 'Unresolved\scan.json') -Raw | ConvertFrom-Json
    if(@($manifest.Videos).Count -ne 0 -or @($manifest.VideoCandidates).Count -ne 1){throw 'Unverified candidate was not separated'}
    'PASS: correct main video downloaded, original title retained, recommendation never requested, unresolved page failed explicitly'
}finally{
    try{Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/stop" -TimeoutSec 3 | Out-Null}catch{}
    $job | Wait-Job -Timeout 5 | Out-Null
    if($job.State -eq 'Running'){Stop-Job $job}
    Remove-Job $job
}
