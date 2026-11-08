# Independent diagnostic logs. No data is uploaded.
function Protect-LogText([string]$Text) {
    $Text=[regex]::Replace($Text,'https?://[^\s<>"'']+', [Text.RegularExpressions.MatchEvaluator]{param($m)
        try {$u=[UriBuilder]::new($m.Value); $u.UserName='';$u.Password='';if($u.Query){$u.Query='REDACTED'};if($u.Fragment){$u.Fragment='REDACTED'};return $u.Uri.AbsoluteUri} catch {return '[URL REDACTED]'}
    })
    $Text=[regex]::Replace($Text,'(?i)((?:authorization|cookie|password|passwd|token|secret|api[_-]?key)\s*[:=]\s*)[^\r\n,;]+','$1[REDACTED]')
    return $Text
}
function Write-Diagnostic {
    param([string]$Stage,[string]$Message,[string]$MediaUrl,[object]$Record,[string]$Severity='Error',[object]$ExitCode)
    $exception=$null; $stack=$null; $httpStatus=$null; $position=$null
    if($Record -is [Management.Automation.ErrorRecord]){
        $exception=$Record.Exception; $stack=$Record.ScriptStackTrace; $position=$Record.InvocationInfo.PositionMessage
    } elseif($Record -is [Exception]){$exception=$Record}
    $chain=New-Object 'Collections.Generic.List[object]'
    while($exception){
        $chain.Add([pscustomobject]@{Type=$exception.GetType().FullName;Message=(Protect-LogText $exception.Message)})
        if($exception.PSObject.Properties['StatusCode'] -and $exception.StatusCode){$httpStatus=[int]$exception.StatusCode}
        $exception=$exception.InnerException
    }
    $entry=[ordered]@{Time=(Get-Date -Format o);RunId=$script:DiagnosticRunId;Severity=$Severity;Stage=$Stage;Url=(Protect-LogText $MediaUrl);Message=(Protect-LogText $Message);ExitCode=$ExitCode;HttpStatus=$httpStatus;Exceptions=@($chain.ToArray());Stack=(Protect-LogText $stack);Position=(Protect-LogText $position)}
    try {
        $entry | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $script:DiagnosticJson -Encoding UTF8
        ('[{0}] [{1}] [{2}] {3} URL={4} ExitCode={5}' -f $entry.Time,$Severity,$Stage,$entry.Message,$entry.Url,$ExitCode) | Add-Content -LiteralPath $script:DiagnosticText -Encoding UTF8
    } catch {Write-Warning ('Unable to write the error log: '+$_.Exception.Message)}
}
function Initialize-Diagnostics([string]$Root) {
    $script:DiagnosticRunId=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8)
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $script:DiagnosticJson=Join-Path $Root ($script:DiagnosticRunId+'.errors.jsonl')
    $script:DiagnosticText=Join-Path $Root ($script:DiagnosticRunId+'.errors.log')
    Write-Diagnostic -Stage 'environment' -Severity Info -Message ('tool=1.1; PowerShell='+$PSVersionTable.PSVersion+'; OS='+[Environment]::OSVersion.VersionString+'; 64bit='+[Environment]::Is64BitProcess)
    Write-Host "Diagnostic log: $script:DiagnosticText"
}
