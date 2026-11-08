$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'video-selection.ps1')
$uri=[Uri]'https://example.test/watch/42'
$cases=@(
    @{Html='<video src="/main.mp4"></video><a href="/other.mp4">Recommendation</a><script>var other="https://ads.test/ad.m3u8"</script>';Expected='https://example.test/main.mp4'},
    @{Html='<video><source src="/main.m3u8"><source src="/backup.mp4"></video>';Expected='https://example.test/main.m3u8'},
    @{Html='<script>var data="https://example.test/recommended.mp4"</script>';Expected=$null},
    @{Html='<video src="/one.mp4"></video><video src="/two.mp4"></video>';Expected=$null},
    @{Html='<video src="/ad.mp4"></video><video id="main-video" src="/main.mp4"></video>';Expected='https://example.test/main.mp4'},
    @{Html='<video hidden src="/hidden.mp4"></video><video src="/main.mp4"></video>';Expected='https://example.test/main.mp4'},
    @{Html='<!-- <video src="/comment.mp4"></video> --><meta property="og:video" content="/main.m3u8?x=1&amp;y=2">';Expected='https://example.test/main.m3u8?x=1&y=2'},
    @{Html='<script>var html="<video src="/fake.mp4"></video>"</script>';Expected=$null},
    @{Html='<meta property="og:video" content="/one.mp4"><meta property="og:video" content="/two.mp4">';Expected=$null}
)
foreach($case in $cases){
    $selection=Get-MainVideoSelection $case.Html $uri 'text/html'
    if($case.Expected){if($selection.Selected.Count -ne 1 -or $selection.Selected[0].Url -ne $case.Expected){throw ('Unexpected selection: '+($selection | ConvertTo-Json -Depth 5))}}
    elseif($selection.Selected.Count -ne 0){throw 'Unconfirmed candidate selected'}
}
$direct=Get-MainVideoSelection '' ([Uri]'https://cdn.test/main.m3u8') 'application/vnd.apple.mpegurl'
if($direct.Selected.Count -ne 1){throw 'Direct manifest not selected'}
if(Test-SpecializedExtractor ([pscustomobject]@{extractor_key='Generic';entries=@(@{url='https://ads.test/ad.mp4'})})){throw 'Generic extractor trusted'}
if(!(Test-SpecializedExtractor ([pscustomobject]@{extractor_key='ExampleDedicated'}))){throw 'Specialized extractor rejected'}
'PASS: 12 selection scenarios, including recommendations, scripts, ambiguity, primary markers, hidden players, metadata, direct manifests, and extractor trust'
