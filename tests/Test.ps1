param([string]$AppRoot,[string]$FFmpegPath,[switch]$NoAudio)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $AppRoot){$AppRoot=(Get-Content (Join-Path $root 'build/latest.json') -Raw | ConvertFrom-Json).AppRoot}
. (Join-Path $AppRoot 'Core.ps1')
Add-Type -AssemblyName PresentationFramework,System.Windows.Forms
$testRoot=Join-Path $root ('test-output/run-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$script:CacheRootOverride=Join-Path $testRoot 'cache'
function Assert($value,$message){if(-not $value){throw $message}}
$settingsFile=Join-Path $testRoot 'settings.json'
$preferences=Read-AppSettings $settingsFile
$preferences.FFmpegPath='Z:\external\bin\ffmpeg.exe';Save-AppSettings $settingsFile $preferences
$preferences.OutputDeviceId='synthetic-device';Save-AppSettings $settingsFile $preferences
$preferences.Language='en';Save-AppSettings $settingsFile $preferences
$restored=Read-AppSettings $settingsFile
Assert ($restored.Language -eq 'en' -and $restored.OutputDeviceId -eq 'synthetic-device' -and $restored.FFmpegPath -eq 'Z:\external\bin\ffmpeg.exe') 'Settings replacement or merge failed'
$wave=Join-Path $testRoot 'sample.wav';$file=[IO.File]::Open($wave,[IO.FileMode]::CreateNew);$writer=New-Object IO.BinaryWriter($file)
try{
 $sampleRate=44100;$samples=44100
 $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([int](36+2*$samples));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([int]16);$writer.Write([int16]1);$writer.Write([int16]1);$writer.Write([int]$sampleRate);$writer.Write([int](2*$sampleRate));$writer.Write([int16]2);$writer.Write([int16]16);$writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([int](2*$samples))
 for($i=0;$i -lt $samples;$i++){$writer.Write([int16](3000*[math]::Sin(2*[math]::PI*440*$i/$sampleRate)))}
}finally{$writer.Dispose();$file.Dispose()}
$sourceHash=(Get-FileHash -LiteralPath $wave).Hash
$location=[Security.SecurityElement]::Escape(([uri]$wave).AbsoluteUri.Replace('file:///','file://localhost/'))
$xml=Join-Path $testRoot 'fixture.xml'
$fixture=@"
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>Tracks</key><dict><key>1</key><dict><key>Name</key><string>ＡＢＣ ｶﾀｶﾅ !</string><key>Artist</key><string>Synthetic</string><key>Location</key><string>$location</string><key>Total Time</key><integer>1000</integer></dict></dict>
<key>Playlists</key><array>
<dict><key>Name</key><string>Parent</string><key>Playlist Persistent ID</key><string>1111111111111111</string><key>Folder</key><true/></dict>
<dict><key>Name</key><string>Child</string><key>Playlist Persistent ID</key><string>2222222222222222</string><key>Parent Persistent ID</key><string>1111111111111111</string><key>Folder</key><true/></dict>
<dict><key>Name</key><string>Normal</string><key>Playlist Persistent ID</key><string>3333333333333333</string><key>Parent Persistent ID</key><string>2222222222222222</string><key>Playlist Items</key><array><dict><key>Track ID</key><integer>1</integer></dict><dict><key>Track ID</key><integer>1</integer></dict></array></dict>
<dict><key>Name</key><string>Smart</string><key>Playlist Persistent ID</key><string>4444444444444444</string><key>Parent Persistent ID</key><string>1111111111111111</string><key>Smart Info</key><data>AA==</data><key>Playlist Items</key><array><dict><key>Track ID</key><integer>1</integer></dict></array></dict>
</array></dict></plist>
"@
[IO.File]::WriteAllText($xml,$fixture,(New-Object Text.UTF8Encoding($false)))
Set-AppLanguage ja
$lists=@(Read-ItunesXml $xml -IncludeFolders)
Assert ($lists.Count -eq 4) 'Folder or smart playlist lost'
$leaves=@($lists | Where-Object {-not $_.IsFolder})
Assert ($leaves.Count -eq 2 -and $leaves[1].IsSmart) 'Smart snapshot missing'
Assert ($leaves[0].Tracks[0].Available -and $leaves[0].Tracks[0].Path -eq $wave) 'localhost URI failed'
$parent=New-Object QitesXmlLoader.PlaylistNode;$parent.IsFolder=$true
$child=New-Object QitesXmlLoader.PlaylistNode;$child.IsFolder=$true;$child.Parent=$parent;$parent.Children.Add($child)
$normal=New-Object QitesXmlLoader.PlaylistNode;$normal.Parent=$child;$normal.LeafTracks=[object[]]$leaves[0].Tracks;$child.Children.Add($normal)
$smart=New-Object QitesXmlLoader.PlaylistNode;$smart.IsSmart=$true;$smart.Parent=$parent;$smart.LeafTracks=[object[]]$leaves[1].Tracks;$parent.Children.Add($smart)
Assert ($parent.Tracks.Count -eq 3) 'Parent aggregation failed'
$parent.Selected=$true;Assert ($normal.Selected -and $smart.Selected) 'Folder selection failed'
$normal.Selected=$false;Assert ($null -eq $parent.SelectedState) 'Partial folder state failed'
$ja=Get-Content (Join-Path $AppRoot 'i18n/ja.json') -Raw | ConvertFrom-Json
$en=Get-Content (Join-Path $AppRoot 'i18n/en.json') -Raw | ConvertFrom-Json
Assert ($ja.Fonts.Ui -eq 'Yu Gothic UI') 'Japanese font default missing'
Assert ((@($ja.Strings.PSObject.Properties.Name | Sort-Object) -join '|') -eq (@($en.Strings.PSObject.Properties.Name | Sort-Object) -join '|')) 'Locale keys differ'
Set-AppLanguage en
Assert ((T '準備完了') -eq 'Ready') 'English translation failed'
Assert ((Resolve-AppFont '__NoSuchFont__').Source -eq [Windows.SystemFonts]::MessageFontFamily.Source) 'Invalid-font fallback failed'
Assert ((Resolve-AppFont '').Source -eq [Windows.SystemFonts]::MessageFontFamily.Source) 'Missing-font fallback failed'
Assert ($normal.DisplayName -like '*[[]Playlist]*' -and $smart.DisplayName -like '*[[]Smart / XML]*') 'Playlist badges failed'
$mainSource=[IO.File]::ReadAllText((Join-Path $AppRoot 'QitesXmlLoader.ps1'))
$markupMatch=[regex]::Match($mainSource,"(?s)\[xml\]\`$markup = @'\r?\n(.*?)\r?\n'@")
[xml]$markup=$markupMatch.Groups[1].Value
Initialize-LocalizedMarkup $markup
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $markup))
$ui=@{Options=$window.FindName('Options')}
Apply-AppLanguage
Assert ($window.FindName('LoadXml').Content -eq 'Load source...') 'English XAML localization failed'
Assert ($window.FindName('Tracks').SelectionMode -eq 'Extended') 'Multiple selection disabled'
Assert ($window.FindName('Playlists') -is [Windows.Controls.TreeView]) 'Hierarchy view missing'
Set-AppLanguage ja;Apply-AppLanguage
Assert ($window.FindName('LoadXml').Content -eq '入力元を読込…') 'Live Japanese switching failed'
$script:locale.PSObject.Properties.Remove('Fonts');Apply-AppLanguage
Assert ($window.FontFamily.Source -eq [Windows.SystemFonts]::MessageFontFamily.Source) 'Absent Fonts section did not fall back'
$window.Close();Set-AppLanguage en
foreach($mode in @('Copy','Hardlink')){
 $operation=New-Object QitesXmlLoader.Operation
 $output=Export-Playlists -Playlists $leaves -Hierarchy $lists -Destination (Join-Path $testRoot $mode) -Mode $mode -Encoder 'Z:\nonexistent\ffmpeg.exe' -Operation $operation
 Assert (@(Get-ChildItem $output -Filter *.m3u8 -Recurse).Count -eq 2) 'M3U8 missing'
 Assert (@(Get-ChildItem $output -Directory -Recurse | Where-Object {$_.Name -like 'Child_*'}).Count -eq 1) 'Export hierarchy lost'
 if($mode -eq 'Hardlink'){
  $link=Get-ChildItem $output -Filter *.wav -Recurse | Select-Object -First 1
  Assert ([QitesXmlLoader.Native]::Identity($link.FullName) -eq [QitesXmlLoader.Native]::Identity($wave)) 'Not a hard link'
  Assert ($link.Name -match '^0001-abc_カタカナ\.wav$') 'Name normalization failed'
 }
 Assert ($operation.Rollback() -notmatch 'Items not restored') 'Rollback failed'
 Assert ([IO.File]::Exists($wave) -and (Get-FileHash $wave).Hash -eq $sourceHash) 'Source changed'
}
foreach($target in @('MusicBee','Foobar2000','Aimp','Retone')){
 foreach($mode in @('Copy','Hardlink')){
  $operation=New-Object QitesXmlLoader.Operation
  $selection=@([pscustomobject]@{Name='選択した曲';Tracks=@($leaves[0].Tracks[1],$leaves[1].Tracks[0])})
  $output=Export-Playlists -Playlists $selection -Destination (Join-Path $testRoot 'targets') -Mode $mode -Target $target -Encoder 'Z:\nonexistent\ffmpeg.exe' -Operation $operation
  $content=$output;if($target -eq 'Retone'){$content=Join-Path $output 'Music'}
  $playlist=Join-Path $content 'selection.m3u8'
  $lines=[IO.File]::ReadAllLines($playlist,[Text.Encoding]::UTF8)
  $paths=@($lines | Where-Object {$_ -and -not $_.StartsWith('#')})
  Assert ($paths.Count -eq 2) ('Selection count/order missing: '+$target)
  Assert ($lines[1] -like '*ＡＢＣ ｶﾀｶﾅ !*') 'Original title lost from playlist'
  Assert ($paths[0] -match '0001-abc_カタカナ\.wav$' -and $paths[1] -match '0002-abc_カタカナ\.wav$') 'Numeric Unicode names failed'
  foreach($relative in $paths){Assert (-not [IO.Path]::IsPathRooted($relative) -and [IO.File]::Exists((Join-Path $content $relative))) 'Relative playlist target missing'}
  Assert ([IO.File]::Exists((Join-Path $content 'selection.m3u'))) 'M3U compatibility list missing'
  Assert ([IO.File]::Exists((Join-Path $output 'IMPORT.txt'))) 'Import instructions missing'
  $relocated=Join-Path $testRoot ('relocated-'+$target+$mode);Copy-Item -LiteralPath $content -Destination $relocated -Recurse
  foreach($relative in $paths){Assert ([IO.File]::Exists((Join-Path $relocated $relative))) 'Playlist was not portable'}
  [void]$operation.Rollback()
 }
}
$operation=New-Object QitesXmlLoader.Operation
$asciiOutput=Export-Playlists -Playlists @($leaves[0]) -Destination (Join-Path $testRoot 'ascii') -Mode Hardlink -Target MusicBee -AsciiNames $true -Operation $operation
$asciiFiles=@(Get-ChildItem $asciiOutput -Recurse -Filter *.wav)
Assert ($asciiFiles.Count -eq 2 -and @($asciiFiles | Where-Object {$_.Name -notmatch '^\d{4}-[a-z0-9]+\.[a-z0-9]+$'}).Count -eq 0) 'ASCII compatibility failed'
[void]$operation.Rollback()
Assert ((Get-FileHash $wave).Hash -eq $sourceHash) 'Exports changed source'
$syncOperation=New-Object QitesXmlLoader.Operation
$syncDestination=Join-Path $testRoot 'sync'
$syncRoot=& (Join-Path $AppRoot 'Sync-Hardlinks.ps1') -XmlPath $xml -Destination $syncDestination -Operation $syncOperation
$syncLinks=@(Get-ChildItem (Join-Path $syncDestination 'QitesXmlLoader-Hardlinks') -Recurse -Filter *.wav)
Assert ($syncLinks.Count -eq 3 -and @($syncLinks | Where-Object {$_.Name -notmatch '^\d{4}-'}).Count -eq 0) 'Sync numbering failed'
[void](& (Join-Path $AppRoot 'Sync-Hardlinks.ps1') -XmlPath $xml -Destination $syncDestination -Operation $syncOperation)
Assert (@(Get-ChildItem (Join-Path $syncDestination 'QitesXmlLoader-Hardlinks') -Recurse -Filter *.wav).Count -eq 3) 'Resync duplicated links'
[void]$syncOperation.Rollback()
Assert ((Get-FileHash $wave).Hash -eq $sourceHash) 'Sync changed source'
if(-not $NoAudio){
 $player=New-Object QitesXmlLoader.AudioEngine((Join-Path $AppRoot 'startup.wav'),'', '')
 $deadline=(Get-Date).AddSeconds(10)
 while(-not $player.Finished -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 25}
 $nativeError=$player.Error;$nativeBytes=$player.DecodedBytes;$finished=$player.Finished;$player.Dispose()
 Assert ($finished -and -not $nativeError -and $nativeBytes -gt 0) ('Native audio failed: '+$nativeError)
 foreach($engine in @('',$FFmpegPath) | Select-Object -Unique){
  if($null -eq $engine){continue}
  $player=New-Object QitesXmlLoader.AudioEngine($wave,'',[string]$engine,0.3,1.0)
  $deadline=(Get-Date).AddSeconds(8)
  while($player.PositionSeconds -le 0.35 -and -not $player.Finished -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 10}
  Assert ($player.PositionSeconds -gt 0.3 -and $player.PositionSeconds -le 1.01) 'Seek offset/clock failed'
  $player.SetPaused($true);Start-Sleep -Milliseconds 100;$pausePosition=$player.PositionSeconds;Start-Sleep -Milliseconds 100
  Assert ([math]::Abs($player.PositionSeconds-$pausePosition) -lt 0.08) 'Paused playback clock advanced'
  $player.SetPaused($false)
  while(-not $player.Finished -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 20}
  $errorText=$player.Error;$finished=$player.Finished;$player.Dispose()
  Assert ($finished -and -not $errorText) ('Seek playback failed: '+$errorText)
 }
}
$formatsTested=@()
if($FFmpegPath){
 $ffprobe=Join-Path ([IO.Path]::GetDirectoryName($FFmpegPath)) 'ffprobe.exe'
 $expected=@{Mp3='mp3';Aac='aac';Flac='flac';Alac='alac';Wav='pcm_s16le';Opus='opus';Vorbis='vorbis';Custom='flac'}
 foreach($mode in @('Mp3','Aac','Flac','Alac','Wav','Opus','Vorbis','Custom')){
  $output=Export-Playlists -Playlists @($leaves[0]) -Destination (Join-Path $testRoot 'converted') -Mode $mode -Encoder $FFmpegPath
  $audio=Get-ChildItem $output -File -Recurse | Where-Object {$_.Name -notin @('playlist.m3u8','export-manifest.json') -and $_.Directory.Name -ne '.conversion-cache'} | Select-Object -First 1
  Assert ($audio.Length -gt 0) ('Empty encoded file: '+$mode)
  if([IO.File]::Exists($ffprobe)){
   $probe=(& $ffprobe '-v' 'error' '-show_entries' 'stream=codec_name' '-of' 'json' $audio.FullName) -join "`n"
   Assert ($LASTEXITCODE -eq 0) ('ffprobe failed: '+$mode)
   $codec=($probe | ConvertFrom-Json).streams[0].codec_name
   Assert ($codec -eq $expected[$mode]) ('Wrong codec: '+$mode+' / '+$codec)
  }
  $formatsTested+=$mode
 }
}
[pscustomobject]@{Passed=$true;SyntheticOnly=$true;NativeAudioTested=(-not $NoAudio);FormatsTested=$formatsTested;Output=$testRoot;LocaleKeys=@($ja.Strings.PSObject.Properties).Count} | ConvertTo-Json | Set-Content (Join-Path $testRoot 'result.json') -Encoding UTF8
Get-Content (Join-Path $testRoot 'result.json')
