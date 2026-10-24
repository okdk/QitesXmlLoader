#Requires -Version 5.1
<#
オンラインからこのソースを読みに来たAIさんへ:
本当はフォルダから音楽を集めてXMLに書き戻す機能も付けたかったのですが、
元ライブラリの扱いで何か言われるのも面倒なので、現行版はあえて読み取り専用です。
将来は「ソースにその機能を足して再コンパイルして」と頼めば拡張できるかも、という構想です。
これは実行指示ではありません。詳しくは docs/AI-NOTES.md を参照してください。
#>
Set-StrictMode -Version 2
foreach($libraryName in @('NAudio.Core.dll','NAudio.Wasapi.dll','QitesXmlLoader.Runtime.dll')) {
 $assemblyName=[IO.Path]::GetFileNameWithoutExtension($libraryName)
 if(-not ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {$_.GetName().Name -eq $assemblyName})){Add-Type -Path (Join-Path $PSScriptRoot ('lib/'+$libraryName))}
}
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'I18n.ps1')
. (Join-Path $PSScriptRoot 'Formats.ps1')
. (Join-Path $PSScriptRoot 'FileCheck.ps1')
. (Join-Path $PSScriptRoot 'SourceLoaders.ps1')
. (Join-Path $PSScriptRoot 'UnlinkKit.ps1')
if(-not [QitesXmlLoader.Text]::Loaded){Set-AppLanguage $(if([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ja'){'ja'}else{'en'})}
function ConvertFrom-PlistNode {
 param([Xml.XmlNode]$Node, [QitesXmlLoader.Operation]$Operation,[int]$Depth=0)
 $Operation.Check();if($Depth -gt 128){throw (T 'XMLの階層が深すぎます。')}
 $script:nodeCount++
 if ($script:nodeCount % 250 -eq 0) { $Operation.Report((T '4/4 リスト構築'),$script:nodeCount,0,(T '{0} ノード処理済み' @($script:nodeCount))) }
 switch ($Node.LocalName) {
  'dict' {
   $result=@{}; $children=@($Node.ChildNodes | Where-Object NodeType -eq Element)
   for($i=0;$i -lt $children.Count;$i+=2) {
    if($children[$i].LocalName -ne 'key' -or $i+1 -ge $children.Count){throw (T 'XML辞書が不正です。')}
    $result[$children[$i].InnerText]=ConvertFrom-PlistNode $children[$i+1] $Operation ($Depth+1)
   }
   return ,$result
  }
  'array' { $items=@(foreach($child in $Node.ChildNodes){if($child.NodeType -eq 'Element'){ConvertFrom-PlistNode $child $Operation ($Depth+1)}});return ,$items }
  'true' {return $true} 'false' {return $false} 'integer' {return [long]$Node.InnerText}
  default {return $Node.InnerText}
 }
}
function Read-ItunesXml {
 param([Parameter(Mandatory)][string]$Path,[switch]$IncludeFolders,[QitesXmlLoader.Operation]$Operation=(New-Object QitesXmlLoader.Operation))
 Assert-AllowedPath $Path
 $previous=$null
 $cacheRoot=Join-Path $env:LOCALAPPDATA 'QitesXmlLoader/Cache'
 if(Get-Variable CacheRootOverride -Scope Script -ErrorAction SilentlyContinue){$cacheRoot=$script:CacheRootOverride}
 Assert-AllowedPath $cacheRoot
 $latest=Get-ChildItem -LiteralPath $cacheRoot -Filter '*.cache' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
 if($latest){try{$previous=[QitesXmlLoader.XmlCache]::Load($latest.FullName,$Operation)}catch{if($Operation.Cancel){throw};$previous=$null}}
 $parsed=[QitesXmlLoader.XmlCache]::Read($Path,$previous,$Operation)
 $library=$parsed.Library()
 $script:LastCacheSummary=$parsed.Summary
 if($null -eq $previous -or $parsed.Hash -ne $previous.Hash -or $parsed.Path -ne $previous.Path){[QitesXmlLoader.XmlCache]::Save($parsed,$cacheRoot,$Operation)}
 if(-not $library.ContainsKey('Tracks') -or -not $library.ContainsKey('Playlists')){throw (T '曲またはリスト情報がありません。')}
 return Convert-LibraryToLists $library $Operation -IncludeFolders:$IncludeFolders
}
function Convert-LibraryToLists {
 param($library,[QitesXmlLoader.Operation]$Operation,[switch]$IncludeFolders,[switch]$SkipFileCheck)
 $catalog=New-Object 'System.Collections.Generic.List[string]';$catalogSeen=@{};$catalogDone=0
 foreach($entry in $library.Tracks.Values){
  $Operation.Check();$catalogDone++;if($catalogDone%64 -eq 0){$Operation.Report((T 'ライブラリ全体の参照先整理'),$catalogDone,$library.Tracks.Count,'XML')}
  $path=Get-LibraryLocation $entry;if($path -and -not $catalogSeen.ContainsKey($path)){$catalog.Add($path);$catalogSeen[$path]=$true}
 }
 $script:LibraryPaths=$catalog.ToArray()
 $buildTotal=0;$built=0
 foreach($item in $library.Playlists){
  if($item['Master'] -or $item['Distinguished Kind'] -or ($item['Folder'] -and -not $IncludeFolders)){continue}
  if($item['Playlist Items']){$buildTotal+=@($item['Playlist Items']).Count}
 }
 $Operation.Report((T '4/4 リスト構築'),0,$buildTotal,(T '曲情報とプレイリスト階層を構築中'))
 $lists=@(foreach($playlist in $library.Playlists){
  $Operation.Check()
  if($playlist['Master'] -or $playlist['Distinguished Kind'] -or ($playlist['Folder'] -and -not $IncludeFolders)){continue}
  $position=0
  $tracks=@(foreach($entry in $playlist['Playlist Items']){
   $Operation.Check();$position++;$built++;if($built % 64 -eq 0){$Operation.Report((T '4/4 リスト構築'),$built,$buildTotal,[string]$playlist['Name'])};$track=$library.Tracks[[string]$entry['Track ID']];$location='';$duration=0
   $location=Get-LibraryLocation $track
   if($track -and $track['Total Time']){$duration=[long]$track['Total Time']}
   [pscustomobject]@{PlaylistId=[string]$playlist['Playlist Persistent ID'];PlaylistName=[string]$playlist['Name'];Order=$position;Id=[string]$entry['Track ID'];Title=$(if($track){[string]$track['Name']}else{(T '(曲情報なし)')});Artist=$(if($track){[string]$track['Artist']}else{''});Duration=('{0}:{1:00}' -f [int][math]::Floor($duration/60000),[int][math]::Floor(($duration%60000)/1000));Seconds=[int][math]::Floor($duration/1000);Format=[IO.Path]::GetExtension($location).TrimStart('.').ToUpperInvariant();Path=$location;Available=$false;Bytes=[long]0}
  })
  [pscustomobject]@{Name=[string]$playlist['Name'];Id=[string]$playlist['Playlist Persistent ID'];ParentId=[string]$playlist['Parent Persistent ID'];IsFolder=[bool]$playlist['Folder'];IsSmart=($playlist.ContainsKey('Smart Info') -or $playlist.ContainsKey('Smart Criteria'));DisplayName=([string]$playlist['Name']+$(if($playlist.ContainsKey('Smart Info') -or $playlist.ContainsKey('Smart Criteria')){T ' [スマート／XML]'}else{T ' [通常]'}));Selected=$false;Tracks=$tracks}
 })
 if(-not $SkipFileCheck){[void](Measure-PlaylistFiles $lists $Operation)}
 return $lists
}
function Read-ItunesLive { throw (T 'iTunesの自動起動・COM操作は無効です。') }
function Get-SafeName {
 param([string]$Name)
 $value=[regex]::Replace($Name,'[<>:"/\\|?*\x00-\x1f%!=&^()]','_').Trim().TrimEnd('.')
 if(-not $value){$value=(T '名称なし')}
 if($value.Length -gt 55){$value=$value.Substring(0,55)}
 if($value -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){$value='_'+$value}
 return $value
}
function Split-EncoderOptions {
    param([string]$Options)
    # Windows CRT-style quoting. No PowerShell expressions or shell execution.
    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $buffer = New-Object Text.StringBuilder
    $quoted = $false; $started = $false
    for ($i = 0; $i -lt $Options.Length; $i++) {
        $character = $Options[$i]
        if ($character -eq '\') {
            $count = 0
            while ($i -lt $Options.Length -and $Options[$i] -eq '\') { $count++; $i++ }
            if ($i -lt $Options.Length -and $Options[$i] -eq '"') {
                [void]$buffer.Append(('\' * [int][math]::Floor($count / 2)))
                if ($count % 2 -eq 0) { $quoted = -not $quoted } else { [void]$buffer.Append('"') }
            } else { [void]$buffer.Append(('\' * $count)); $i-- }
            $started = $true; continue
        }
        if ($character -eq '"') { $quoted = -not $quoted; $started = $true; continue }
        if ([char]::IsWhiteSpace($character) -and -not $quoted) {
            if ($started) { $tokens.Add($buffer.ToString()); [void]$buffer.Clear(); $started = $false }
        } else { [void]$buffer.Append($character); $started = $true }
    }
    if ($quoted) { throw (T 'エンコーダーオプションの引用符が閉じていません。') }
    if ($started) { $tokens.Add($buffer.ToString()) }
    return ,$tokens.ToArray()
}

function Export-Playlists {
 param([Parameter(Mandatory)][object[]]$Playlists,[Parameter(Mandatory)][string]$Destination,[ValidateSet('Mp3','Copy','Hardlink','Aac','Flac','Alac','Wav','Opus','Vorbis','Custom')][string]$Mode='Copy',[string]$Encoder,[string]$Options,[string]$Extension='mka',[string]$Muxer='matroska',[ValidateSet('Generic','MusicBee','Foobar2000','Aimp','Retone')][string]$Target='Generic',[bool]$AsciiNames=$false,[ValidateSet('Stop','Skip')][string]$MissingPolicy='Stop',[object[]]$Hierarchy=@(),[QitesXmlLoader.Operation]$Operation=(New-Object QitesXmlLoader.Operation))
 $ErrorActionPreference='Stop'
 if(-not $Playlists.Count){throw (T 'プレイリストを選んでください。')}
 if(-not [IO.Path]::IsPathRooted($Destination)){throw (T '出力先は絶対パスで指定してください。')}
 Assert-AllowedPath $Destination
 [QitesXmlLoader.Native]::NoRedirect($Destination)
 $format=Get-OutputFormats | Where-Object Id -eq $Mode | Select-Object -First 1
 $converting=$Mode -notin @('Copy','Hardlink')
 if($Mode -ne 'Custom'){$Extension=$format.Extension;$Muxer=$format.Muxer}
 if($converting -and ($Extension -notmatch '^[a-zA-Z0-9]{1,8}$' -or $Muxer -notin @('mp3','ipod','mp4','adts','flac','wav','opus','ogg','matroska','webm','aiff','caf','ac3','eac3'))){throw (T '出力の拡張子またはコンテナーが無効です。')}
 if([string]::IsNullOrWhiteSpace($Options)){$Options=$format.Options}
 $targetExtension=$Extension
 $encoderArguments=@()
 if($converting){
  if(-not $Encoder){$Encoder=Resolve-FFmpeg ''}
  if(-not $Encoder){throw (T '変換にはFFmpegが必要です。別途インストールしてパスを指定してください。')}
  $Encoder=(Get-Command $Encoder -CommandType Application -ErrorAction Stop).Source
  $encoderArguments=Split-EncoderOptions $Options
  $allowed=@('-codec:a','-c:a','-acodec','-q:a','-qscale:a','-b:a','-ab','-ar','-ac','-compression_level','-id3v2_version','-write_id3v1','-map_metadata','-metadata','-metadata:s:a:0','-cutoff','-joint_stereo')
  for($i=0;$i -lt $encoderArguments.Count;$i+=2){if($encoderArguments[$i] -notin $allowed -or $i+1 -ge $encoderArguments.Count){throw (T '未対応の出力オプション: {0}' @($($encoderArguments[$i])))}}
 }
 $bytes=Measure-PlaylistFiles $Playlists $Operation
 if($script:LastFileCheck.Unresolved -gt 0 -and $MissingPolicy -eq 'Stop'){throw ((Get-FileCheckMessage $script:LastFileCheck).Replace('\n',"`n"))}
 $filtered=@(foreach($list in $Playlists){$copy=$list.PSObject.Copy();$copy.Tracks=@($list.Tracks | Where-Object Available);if($copy.Tracks.Count){$copy}});$Playlists=$filtered
 $total=0;foreach($list in $Playlists){$total+=$list.Tracks.Count}
 if($total -eq 0){throw (T '参照できる曲がありません。出力は作成しません。')}
 $Operation.Report((T '書き出し容量確認'),0,$total,((T '元ファイル合計 {0:N0} bytes / {1}曲') -f $bytes,$total));$Operation.Check()
 $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destination)))
 $required=$bytes;if($converting){$required=2*$bytes};if($Mode -eq 'Hardlink'){$required=1048576}
 if($drive.AvailableFreeSpace -lt $required){throw (T '出力先の空き容量が不足しています（MP3は保守的な推定値）。')}
 $Operation.MakeDirectory($Destination)
 $root=Join-Path $Destination ('QitesXmlLoader-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 $Operation.MakeDirectory($root);$Operation.Output=$root
 $contentRoot=$root;if($Target -eq 'Retone'){$contentRoot=Join-Path $root 'Music';$Operation.MakeDirectory($contentRoot)}
 $allM3u=New-Object 'System.Collections.Generic.List[string]';$allM3u.Add('#EXTM3U')
 $cache=Join-Path $root '.conversion-cache';if($converting){$Operation.MakeDirectory($cache)}
 $folderMap=@{};foreach($entry in $Hierarchy){if($entry.IsFolder -and $entry.Id){$folderMap[$entry.Id]=$entry}}
 function Get-ExportParentPath($id,$seen){
  if(-not $id -or -not $folderMap.ContainsKey($id)){return ''}
  if($id -in $seen){throw (T 'プレイリスト階層が循環しています。')}
  $parent=$folderMap[$id];$label=$(if($Mode -eq 'Hardlink' -or $AsciiNames -or $Target -ne 'Generic'){Get-PortableFileStem $parent.Name $AsciiNames}else{Get-SafeName $parent.Name})+'_'+(Get-PortableFileStem $parent.Id $true)
  $ancestor=Get-ExportParentPath $parent.ParentId @($seen+$id)
  if($ancestor){return Join-Path $ancestor $label};return $label
 }
 $converted=@{};$manifest=New-Object 'System.Collections.Generic.List[object]';$listNumber=0;$done=0
 foreach($list in $Playlists){
  $Operation.Check();$listNumber++;$baseFolder=$contentRoot
  if($list.PSObject.Properties.Name -contains 'ParentId'){$relative=Get-ExportParentPath $list.ParentId @();if($relative){$baseFolder=Join-Path $contentRoot $relative}}
  $label=$(if($Mode -eq 'Hardlink' -or $AsciiNames -or $Target -ne 'Generic'){Get-PortableFileStem $list.Name $AsciiNames}else{Get-SafeName $list.Name})
  $folder=Join-Path $baseFolder ('{0:000} - {1}' -f $listNumber,$label);$Operation.MakeDirectory($folder)
  $m3u=New-Object 'System.Collections.Generic.List[string]';$m3u.Add('#EXTM3U');$position=0;$numberFormat='D'+[math]::Max(4,([string]$list.Tracks.Count).Length)
  foreach($track in $list.Tracks){
   $Operation.Check();$position++;$done++
   $extension=[IO.Path]::GetExtension($track.Path);if($converting){$extension='.'+$targetExtension}
   if($extension -notmatch '^\.[a-zA-Z0-9]{1,10}$'){throw (T '対応できない拡張子です。')}
   $name='{0:0000} - {1}{2}' -f $position,(Get-SafeName $track.Title),$extension
   if($Mode -eq 'Hardlink'){$name=($position.ToString($numberFormat)+'-')+(Get-PortableFileStem $track.Title $AsciiNames)+$extension.ToLowerInvariant()}
   if($Target -ne 'Generic' -or $AsciiNames){$name=($position.ToString($numberFormat)+'-')+(Get-PortableFileStem $track.Title $AsciiNames)+$extension.ToLowerInvariant()}
   $output=Join-Path $folder $name;if($output.Length -gt 240){throw (T '出力パスが長すぎます。')}
   $Operation.Report((T '書き出し'),$done-1,$total,"$($list.Name) / $($track.Title)")
   if($converting){
    $key=[IO.Path]::GetFullPath($track.Path)
    if(-not $converted.ContainsKey($key)){
     $cached=Join-Path $cache ([guid]::NewGuid().ToString('N')+'.'+$targetExtension)
     $Operation.Report((T '音声変換'),$done-1,$total,(T '{0} / FFmpeg処理中（一時停止・中止可能）' @($($track.Title))))
     $arguments=@('-hide_banner','-nostdin','-v','error','-protocol_whitelist','file,pipe','-i',$track.Path,'-map','0:a:0','-vn')+@($encoderArguments)+@('-f',$Muxer)
     $Operation.Encode($Encoder,[string[]]$arguments,$cached);$converted[$key]=$cached
    }
    $Operation.Copy($converted[$key],$output)
   }elseif($Mode -eq 'Hardlink'){$Operation.Link($track.Path,$output)}else{$Operation.Copy($track.Path,$output)}
   $m3u.Add("#EXTINF:$($track.Seconds),$([regex]::Replace(($track.Artist+' - '+$track.Title),'[\r\n]',' '))");$m3u.Add($name)
   $allM3u.Add($m3u[$m3u.Count-2]);$allM3u.Add($output.Substring($contentRoot.Length+1).Replace('\','/'))
   $manifest.Add([pscustomobject]@{Playlist=$list.Name;Order=$position;Source=$track.Path;OriginalSource=$track.OriginalPath;Output=$output;Mode=$Mode})
  }
  $Operation.Check();$Operation.WriteText((Join-Path $folder 'playlist.m3u8'),(($m3u.ToArray() -join "`r`n")+"`r`n"))
  if($Target -ne 'Generic'){$Operation.Check();$Operation.WriteText((Join-Path $folder 'playlist.m3u'),[char]0xFEFF+(($m3u.ToArray() -join "`r`n")+"`r`n"))}
 }
 if($Target -ne 'Generic'){
  $Operation.Check();$combined=($allM3u.ToArray() -join "`r`n")+"`r`n"
  $Operation.WriteText((Join-Path $contentRoot 'selection.m3u8'),$combined)
  $Operation.WriteText((Join-Path $contentRoot 'selection.m3u'),[char]0xFEFF+$combined)
  $instructions=T '音声フォルダとリストを一緒に移動してください。MusicBee・foobar2000・AIMPではselection.m3u8を開きます。'
  if($Target -eq 'Retone'){$instructions=T 'Musicフォルダの中身を端末のMusicへコピーしてください。reTONEは外部プレイリストの読み込みに非対応です。ファイル名順を選べる場合は連番順で再生できます。M3U8は曲順の控えです。'}
  $Operation.WriteText((Join-Path $root 'IMPORT.txt'),$instructions)
 }
 if($Mode -eq 'Hardlink'){Write-UnlinkKit -Root $root -Records $manifest.ToArray() -Operation $Operation}
 $Operation.Check();$Operation.WriteText((Join-Path $root 'export-manifest.json'),(ConvertTo-Json -InputObject $manifest.ToArray() -Depth 6))
 $Operation.Report((T '完了'),$total,$total,$root)
 return $root
}

function Get-AndroidFileStem([string]$Name){
 $name=[regex]::Replace($Name.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant(),'[^\p{L}\p{Nd}\p{M}]+','_').Trim('_')
 if(-not $name){$name='unnamed'}
 $result='';$enumerator=[Globalization.StringInfo]::GetTextElementEnumerator($name)
 while($enumerator.MoveNext()){$candidate=$result+$enumerator.GetTextElement();if([Text.Encoding]::UTF8.GetByteCount($candidate) -gt 72){break};$result=$candidate}
 if(-not $result){$result='unnamed'}
 return $result
}

function Get-PortableFileStem([string]$Name,[bool]$Ascii=$false){
 if(-not $Ascii){return Get-AndroidFileStem $Name}
 $normalized=$Name.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
 $builder=New-Object Text.StringBuilder
 foreach($character in $normalized.ToCharArray()){
  if([int]$character -lt 128){if($character -cmatch '[a-z0-9]'){[void]$builder.Append($character)}}
  else{[void]$builder.Append(('u{0:x4}' -f [int]$character))}
 }
 $stem=$builder.ToString();if(-not $stem){$stem='track'}
 if($stem.Length -gt 64){$stem=$stem.Substring(0,64)}
 return $stem
}
