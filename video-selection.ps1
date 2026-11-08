function Get-TagAttributes([string]$Tag) {
    $attrs=@{}
    foreach($a in [regex]::Matches($Tag,'(?is)([\w:-]+)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))')){
        $value=$a.Groups[2].Value
        if(!$a.Groups[2].Success){$value=$a.Groups[3].Value}
        if(!$a.Groups[2].Success -and !$a.Groups[3].Success){$value=$a.Groups[4].Value}
        $attrs[$a.Groups[1].Value.ToLowerInvariant()]=[Net.WebUtility]::HtmlDecode($value)
    }
    return $attrs
}
function Get-MainVideoSelection([string]$Html,[Uri]$PageUri,[string]$ContentType) {
    $players=New-Object 'Collections.Generic.List[object]'
    $evidence=New-Object 'Collections.Generic.List[object]'
    function NormalizeVideoUrl([string]$Link) {
        if(!$Link){return $null}
        try{$u=[Uri]::new($PageUri,[Net.WebUtility]::HtmlDecode($Link).Replace('\/','/'));if($u.Scheme -in @('http','https')){return $u.AbsoluteUri}}catch{}
        return $null
    }
    function SelectionResult([object[]]$Selected,[string]$Reason){
        return [pscustomobject]@{Selected=@($Selected);Reason=$Reason;Evidence=@($evidence.ToArray())}
    }
    if($ContentType -like 'video/*' -or $ContentType -match '(?i)(mpegurl|dash\+xml)' -or ($ContentType -eq 'application/octet-stream' -and $PageUri.AbsolutePath -match '(?i)\.(mp4|webm|mkv|mov|m3u8|mpd)$')){
        return SelectionResult @([pscustomobject]@{Url=$PageUri.AbsoluteUri;Name='';Source='direct-response'}) 'Direct video or streaming manifest response'
    }
    # Script text and comments are evidence candidates, never rendered players.
    $clean=[regex]::Replace($Html,'(?is)<!--.*?-->|<script\b[^>]*>.*?</script>','')
    foreach($v in [regex]::Matches($clean,'(?is)<video\b([^>]*)>(.*?)</video\s*>')){
        $attrs=Get-TagAttributes $v.Groups[1].Value
        if($v.Groups[1].Value -match '(?i)(?:^|\s)hidden(?:\s|=|$)' -or $attrs['aria-hidden'] -eq 'true' -or $attrs['style'] -match '(?i)display\s*:\s*none'){continue}
        $sources=New-Object 'Collections.Generic.List[string]'
        $src=NormalizeVideoUrl $attrs['src'];if($src){$sources.Add($src)}
        foreach($s in [regex]::Matches($v.Groups[2].Value,'(?is)<source\b[^>]*>')){
            $a=Get-TagAttributes $s.Value; $src=NormalizeVideoUrl $a['src'];if($src -and !$sources.Contains($src)){$sources.Add($src)}
        }
        if(!$sources.Count){continue}
        $primary=$attrs['id'] -match '^(main[-_]?video|primary[-_]?video|main[-_]?player|primary[-_]?player)$' -or $attrs['data-main-video'] -eq 'true'
        $player=[pscustomobject]@{Url=$sources[0];Name='';Source='video-player';Primary=$primary;Alternatives=@($sources.ToArray())}
        $players.Add($player);$evidence.Add($player)
    }
    $main=@($players | Where-Object Primary)
    if($main.Count -eq 1){return SelectionResult @($main[0]) 'Explicit main player'}
    if($main.Count -gt 1){return SelectionResult @() 'Ambiguous: multiple main players'}
    if($players.Count -eq 1){return SelectionResult @($players[0]) 'Single visible HTML video player'}
    if($players.Count -gt 1){return SelectionResult @() 'Ambiguous: multiple visible players'}
    $metadata=New-Object 'Collections.Generic.List[string]'
    foreach($m in [regex]::Matches($clean,'(?is)<meta\b[^>]*>')){
        $a=Get-TagAttributes $m.Value
        if($a['property'] -in @('og:video','og:video:url','og:video:secure_url')){
            $src=NormalizeVideoUrl $a['content'];if($src -and $src -match '(?i)\.(mp4|m3u8|mpd|webm|mov|mkv)(?:[?#]|$)' -and !$metadata.Contains($src)){$metadata.Add($src)}
        }
    }
    foreach($src in $metadata){$evidence.Add([pscustomobject]@{Url=$src;Source='og-video'})}
    if($metadata.Count -eq 1){return SelectionResult @([pscustomobject]@{Url=$metadata[0];Name='';Source='og-video'}) 'Explicit page video metadata'}
    if($metadata.Count -gt 1){return SelectionResult @() 'Ambiguous: conflicting page video metadata'}
    return SelectionResult @() 'No confirmed main video. Script URLs, links, and recommendations are not trusted players.'
}
function Test-SpecializedExtractor([object]$Info) {
    if(!$Info){return $false}
    $key=[string]$Info.extractor_key;if(!$key){$key=[string]$Info.extractor}
    return ![string]::IsNullOrWhiteSpace($key) -and $key -notmatch '(?i)^generic$'
}
