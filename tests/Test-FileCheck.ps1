param([string]$AppRoot)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $AppRoot){$AppRoot=(Get-Content (Join-Path $root 'build/latest.json') -Raw | ConvertFrom-Json).AppRoot}
. (Join-Path $AppRoot 'Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$case=Join-Path $root ('test-output/files-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($case) | Out-Null
$script:CacheRootOverride=Join-Path $case 'cache'
foreach($dir in @('actual','duplicate','stale','outside')){[IO.Directory]::CreateDirectory((Join-Path $case $dir)) | Out-Null}
$actual=Join-Path $case 'actual/song.wav';$duplicate=Join-Path $case 'duplicate/song.wav'
$outside=Join-Path $case 'outside/absent.wav'
[IO.File]::WriteAllText($actual,'synthetic file availability test')
[IO.File]::WriteAllText($outside,'not registered in XML; never adopt')
$hash=(Get-FileHash $actual).Hash
$old=Join-Path $case 'old/song.wav';$stale=Join-Path $case 'stale/song.wav';$absent=Join-Path $case 'old/absent.wav'
function Track($path,$id){return [pscustomobject]@{PlaylistId='1111111111111111';PlaylistName='Synthetic';Order=$id;Id=$id;Title=('Track'+$id);Artist='Synthetic';Path=$path;Available=$false;Bytes=0L;Seconds=1;Format='WAV'}}
$missing=Track $old 1;$unregistered=Track $absent 2
$lists=@([pscustomobject]@{Name='Synthetic';Tracks=@($missing,$unregistered)})
$script:LibraryPaths=@($old,$stale,$actual,$actual.ToUpperInvariant());$script:ResolveLibraryNames=$false
[void](Measure-PlaylistFiles $lists (New-Object QitesXmlLoader.Operation))
Assert ($script:LastFileCheck.Missing -eq 2 -and -not $missing.Available) 'Disabled option adopted a candidate'
$script:ResolveLibraryNames=$true
[void](Measure-PlaylistFiles $lists (New-Object QitesXmlLoader.Operation))
Assert ($missing.Available -and $missing.Path -eq $actual -and $missing.OriginalPath -eq $old) 'Several XML candidates with one existing file did not resolve'
Assert ($script:LastFileCheck.Resolved -eq 1 -and $script:LastFileCheck.Missing -eq 1) 'Resolved/missing counts incorrect'
Assert (-not $unregistered.Available) 'Searched a directory or adopted an unregistered file'
[IO.File]::WriteAllText($duplicate,'another existing file with the same basename')
$script:LibraryPaths=@($old,$stale,$actual,$duplicate)
[void](Measure-PlaylistFiles $lists (New-Object QitesXmlLoader.Operation))
Assert (-not $missing.Available -and $script:LastFileCheck.Ambiguous -eq 1 -and $script:LastFileCheck.Issues[0].ExistingCandidates -eq 2) 'Two existing files were silently chosen'
$script:LibraryPaths=@($old,$stale)
[void](Measure-PlaylistFiles $lists (New-Object QitesXmlLoader.Operation))
Assert ($script:LastFileCheck.Missing -eq 2) 'Zero existing candidates should stay missing'
$script:LibraryPaths=@($old,$actual)
$bad=Track (Join-Path $case 'actual') 3
$errorLists=@([pscustomobject]@{Name='Synthetic';Tracks=@($missing,$unregistered,$bad,$unregistered)})
[void](Measure-PlaylistFiles $errorLists (New-Object QitesXmlLoader.Operation))
Assert ($script:LastFileCheck.Errors -eq 1 -and $script:LastFileCheck.Missing -eq 2 -and $script:LastFileCheck.MissingFiles -eq 1) 'Errors/duplicate-row counts incorrect'
$rejected=$false;$stopOperation=New-Object QitesXmlLoader.Operation
try{[void](Export-Playlists $errorLists (Join-Path $case 'stop-output') -Mode Copy -MissingPolicy Stop -Operation $stopOperation)}catch{$rejected=$true}
Assert ($rejected -and -not [IO.Directory]::Exists((Join-Path $case 'stop-output'))) 'Stop policy created output'
foreach($mode in @('Copy','Hardlink')){
 $operation=New-Object QitesXmlLoader.Operation
 $output=Export-Playlists $errorLists (Join-Path $case 'skip-output') -Mode $mode -MissingPolicy Skip -Operation $operation
 $files=@(Get-ChildItem $output -Recurse -Filter *.wav)
 Assert ($files.Count -eq 1) 'Skip policy exported missing/invalid files'
 $paths=@(Get-Content ($files[0].Directory.FullName+'/playlist.m3u8') | Where-Object {$_ -and -not $_.StartsWith('#')})
 Assert ($paths.Count -eq 1) 'Skipped tracks remained in playlist'
 [void]$operation.Rollback()
}
$allMissing=@([pscustomobject]@{Name='AllMissing';Tracks=@($unregistered)})
$rejected=$false
try{[void](Export-Playlists $allMissing (Join-Path $case 'empty-output') -MissingPolicy Skip)}catch{$rejected=$true}
Assert ($rejected -and -not [IO.Directory]::Exists((Join-Path $case 'empty-output'))) 'All-missing export created empty output'
# The candidate is in Tracks but not in any playlist: still part of the library.
$xml=Join-Path $case 'fixture.xml'
$oldUri=[Security.SecurityElement]::Escape(([uri]$old).AbsoluteUri)
$actualUri=[Security.SecurityElement]::Escape(([uri]$actual).AbsoluteUri)
$staleUri=[Security.SecurityElement]::Escape(([uri]$stale).AbsoluteUri)
$fixture=@"
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Tracks</key><dict>
<key>1</key><dict><key>Name</key><string>Moved</string><key>Location</key><string>$oldUri</string><key>Total Time</key><integer>1000</integer></dict>
<key>2</key><dict><key>Name</key><string>Other registration</string><key>Location</key><string>$actualUri</string></dict>
<key>3</key><dict><key>Name</key><string>Stale registration</string><key>Location</key><string>$staleUri</string></dict>
</dict><key>Playlists</key><array><dict><key>Name</key><string>Synthetic</string><key>Playlist Persistent ID</key><string>1111111111111111</string><key>Playlist Items</key><array><dict><key>Track ID</key><integer>1</integer></dict></array></dict></array></dict></plist>
"@
[IO.File]::WriteAllText($xml,$fixture,(New-Object Text.UTF8Encoding($false)))
$xmlHash=(Get-FileHash $xml).Hash
$loaded=@(Read-ItunesXml $xml)
Assert ($loaded[0].Tracks[0].Path -eq $actual -and $script:LibraryPaths.Count -eq 3) 'Candidate outside playlists was not indexed'
$cached=[QitesXmlLoader.XmlCache]::Load((Get-ChildItem $script:CacheRootOverride -Filter *.cache | Select-Object -First 1).FullName,(New-Object QitesXmlLoader.Operation))
$fromCache=@(Convert-LibraryToLists $cached.Library() (New-Object QitesXmlLoader.Operation))
Assert ($fromCache[0].Tracks[0].Path -eq $actual) 'Cache lost full library candidate paths'
$operation=New-Object QitesXmlLoader.Operation
[void](& (Join-Path $AppRoot 'Sync-Hardlinks.ps1') -XmlPath $xml -Destination (Join-Path $case 'sync') -UseLibraryNames $true -Operation $operation)
Assert (@(Get-ChildItem (Join-Path $case 'sync') -Recurse -Filter *.wav).Count -eq 1) 'Sync did not use recovered path'
[void]$operation.Rollback()
Assert ((Get-FileHash $actual).Hash -eq $hash -and (Get-FileHash $xml).Hash -eq $xmlHash) 'Original audio/XML changed'
$lockedOperation=New-Object QitesXmlLoader.Operation
$lockedFolder=Join-Path $case 'locked-output';$lockedOperation.MakeDirectory($lockedFolder)
$lockedFile=Join-Path $lockedFolder 'owned.txt';$lockedOperation.WriteText($lockedFile,'owned test output')
$lock=[IO.File]::Open($lockedFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{
 $workerResult=@{}
 & (Join-Path $AppRoot 'Worker.ps1') -AppRoot $AppRoot -Kind Rollback -Arguments @{CacheRoot=$script:CacheRootOverride} -Operation $lockedOperation -Result $workerResult
 Assert ($workerResult.State -eq 'Failed' -and -not $lockedOperation.RollbackComplete -and [IO.File]::Exists($lockedFile)) 'Partial rollback was reported complete'
}finally{$lock.Dispose()}
$workerResult=@{}
& (Join-Path $AppRoot 'Worker.ps1') -AppRoot $AppRoot -Kind Rollback -Arguments @{CacheRoot=$script:CacheRootOverride} -Operation $lockedOperation -Result $workerResult
Assert ($workerResult.State -eq 'Complete' -and $lockedOperation.RollbackComplete -and -not [IO.Directory]::Exists($lockedFolder)) 'Rollback could not be retried'
foreach($relative in @('qites-relative-'+[guid]::NewGuid().ToString('N'),'   ')){
 $rejected=$false
 try{[void](& (Join-Path $AppRoot 'Sync-Hardlinks.ps1') -XmlPath $xml -Destination $relative -MissingPolicy Skip)}catch{$rejected=$true}
 Assert $rejected 'Sync accepted a relative/blank output path'
}
$settings=Read-AppSettings (Join-Path $case 'settings.json');$settings.MissingPolicy='Skip';$settings.ResolveLibraryNames=$true
Save-AppSettings (Join-Path $case 'settings.json') $settings
$restored=Read-AppSettings (Join-Path $case 'settings.json')
Assert ($restored.MissingPolicy -eq 'Skip' -and $restored.ResolveLibraryNames -eq $true) 'File options were not saved'
$operation=New-Object QitesXmlLoader.Operation;$operation.Cancel=1;$cancelled=$false
try{[void](Measure-PlaylistFiles $lists $operation)}catch{$cancelled=$true}
Assert $cancelled 'File check ignored cancellation'
Assert (Test-NetworkPath '\\qites-test.invalid\share\song.wav') 'UNC path not recognized'
Assert (Test-NetworkPath '//qites-test.invalid/share/song.wav') 'Slash UNC path not recognized'
Assert (Test-NetworkPath '\\?\UNC\qites-test.invalid\share\song.wav') 'Extended UNC path not recognized'
Assert (-not (Test-NetworkPath '\\?\C:\Music\song.wav')) 'Local extended path blocked'
$originalProbe=(Get-Command Get-PhysicalFileState).ScriptBlock;$originalNetworkProbe=(Get-Command Get-PhysicalNetworkState).ScriptBlock;$script:probeCount=0;$script:networkProbeCount=0
Set-Item Function:\Get-PhysicalFileState -Value {param([string]$Path);$script:probeCount++;return [pscustomobject]@{Exists=$true;Bytes=123L;Error=''}}
Set-Item Function:\Get-PhysicalNetworkState -Value {param([string]$Root);$script:networkProbeCount++;return [pscustomobject]@{Connected=$true;Error=''}}
[QitesXmlLoader.NetworkMemory]::Reset()
try{
 $script:AllowNetworkPaths=$false
 $blocked=Get-FileCheckState '\\qites-test.invalid\share\song.wav'
 Assert (-not $blocked.Exists -and $blocked.Error -and $script:probeCount -eq 0) 'Network probe happened before consent'
 $script:AllowNetworkPaths=$true
 $allowed=Get-FileCheckState '\\qites-test.invalid\share\song.wav'
 Assert ($allowed.Exists -and $script:probeCount -eq 1) 'Network opt-in did not reach mocked file I/O'
 [void](Get-FileCheckState '\\qites-test.invalid\share\other.wav')
 Assert ($script:networkProbeCount -eq 1) 'Same NAS share was connected more than once'
 [QitesXmlLoader.NetworkMemory]::Reset();$script:networkProbeCount=0;$script:probeCount=0
 Set-Item Function:\Get-PhysicalNetworkState -Value {param([string]$Root);$script:networkProbeCount++;return [pscustomobject]@{Connected=$false;Error='Mock offline share'}}
 [void](Get-FileCheckState '\\qites-test.invalid\share\song.wav');[void](Get-FileCheckState '\\qites-test.invalid\share\other.wav')
 Assert ($script:networkProbeCount -eq 1 -and $script:probeCount -eq 0) 'Offline NAS retried per file'
 Assert (-not (Resolve-FFmpeg '\\qites-test.invalid\share\ffmpeg.exe')) 'Offline network encoder unexpectedly resolved'
 Assert (-not (Resolve-FFmpeg '\\qites-test.invalid\share\ffmpeg.exe')) 'Offline network encoder unexpectedly resolved twice'
 Assert (-not (Test-AllowedSourceExists '\\qites-test.invalid\share\Library.xml' file)) 'Startup bypassed offline share memory'
 Assert (-not (Test-AllowedSourceExists '\\qites-test.invalid\share\music' folder)) 'Folder startup bypassed offline share memory'
 Assert ($script:networkProbeCount -eq 1) 'Encoder or startup repeated a failed NAS connection'
 $script:AllowNetworkPaths=$false;$script:probeCount=0
 $networkXml=Join-Path $case 'network.xml'
 [IO.File]::WriteAllText($networkXml,$fixture.Replace($oldUri,'file://qites-test.invalid/share/song.wav').Replace($actualUri,'file://qites-test.invalid/share/song.wav').Replace($staleUri,'file://qites-test.invalid/share/song.wav'))
 [void](Read-ItunesXml $networkXml)
 Assert ($script:probeCount -eq 0 -and $script:LastFileCheck.Errors -eq 1) 'XML import probed a remote host'
}finally{Set-Item Function:\Get-PhysicalFileState -Value $originalProbe;Set-Item Function:\Get-PhysicalNetworkState -Value $originalNetworkProbe;$script:AllowNetworkPaths=$false;[QitesXmlLoader.NetworkMemory]::Reset()}
$deepXml=Join-Path $case 'deep.xml'
$nested=('<array>'*1000)+'<string>value</string>'+('</array>'*1000)
[IO.File]::WriteAllText($deepXml,'<plist><dict><key>Tracks</key><dict><key>1</key><dict><key>Nested</key>'+$nested+'</dict></dict><key>Playlists</key><array/></dict></plist>')
$rejected=$false;try{[void](Read-ItunesXml $deepXml)}catch{$rejected=$true}
Assert $rejected 'Excessive XML depth was not rejected'
[void](Read-ItunesXml $xml)
Assert ($script:LastFileCheck.Resolved -eq 1) 'A valid load failed after rejecting deep XML'
[pscustomobject]@{Passed=$true;SyntheticOnly=$true;XMLUnchanged=$true;SourceUnchanged=$true;Output=$case} | ConvertTo-Json | Set-Content (Join-Path $case 'result.json') -Encoding UTF8
Get-Content (Join-Path $case 'result.json')
