$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) 'media-downloader.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors){throw 'Source parse failed'}
foreach($name in @('SafeName','DirectVideoName')){
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(!$node){throw "Function missing: $name"}
    . ([scriptblock]::Create($node.Extent.Text))
}
$title=-join @([char]0x5ac1,[char]0x91d1,[char]0x9497)
$label=([string][char]0x7b2c)+'1'+([string][char]0x96c6)
$expected=$title+' '+([string][char]0x7b2c)+'01'+([string][char]0x96c6)
if((SafeName $title) -cne $title){throw 'Unicode title was changed'}
if((DirectVideoName $title $label 1 30) -cne $expected){throw 'Original episode naming was not preserved'}
if((DirectVideoName $title '' 1 1) -cne $title){throw 'Single-video title was changed'}
if((DirectVideoName 'Series' 'Trailer' 1 2) -cne 'Series Trailer'){throw 'Original label was changed'}
if((SafeName 'A:B/C') -ne 'A_B_C'){throw 'Invalid filename characters were not sanitized'}
'PASS: Unicode titles, original episode labels, single video titles, named clips, Windows filename sanitization'
