#Requires -Version 5.1
param([Parameter(Mandatory)][string]$XmlPath,[Parameter(Mandatory)][string]$Destination,[ValidateSet('Stop','Skip')][string]$MissingPolicy='Stop',[bool]$UseLibraryNames=$false,[bool]$AllowNetwork=$false, $Operation)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$script:ResolveLibraryNames=$UseLibraryNames
$script:AllowNetworkPaths=$AllowNetwork
if ($null -eq $Operation) { $Operation=New-Object QitesXmlLoader.Operation }
# Only XML snapshots are read. Never activate or automate iTunes.
$lists = @(Read-ItunesXml -Path $XmlPath -IncludeFolders -Operation $Operation)
if($script:LastFileCheck.Unresolved -gt 0 -and $MissingPolicy -eq 'Stop'){throw ((Get-FileCheckMessage $script:LastFileCheck).Replace('\n',"`n"))}
if ([string]::IsNullOrWhiteSpace($Destination) -or -not [IO.Path]::IsPathRooted($Destination)) { throw (T '絶対パスを指定してください。') }
Assert-AllowedPath $Destination
$Destination = [IO.Path]::GetFullPath($Destination)
# Reject junction/symlink ancestors so writes cannot be redirected into music.
$ancestor = $Destination
while ($ancestor) {
 if (Test-Path -LiteralPath $ancestor) {
  if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (T '出力先に再解析ポイントは使用できません。') }
 }
 $ancestor = [IO.Path]::GetDirectoryName($ancestor)
}
$root = Join-Path $Destination 'QitesXmlLoader-Hardlinks'
if (Test-Path -LiteralPath $root) {
 if (-not (Test-Path -LiteralPath (Join-Path $root '.qitesxmlloader-root'))) { throw (T '既存の管理外フォルダには書き込めません。') }
}
$Operation.MakeDirectory($root); $Operation.Output=$root
$utf8 = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path -LiteralPath (Join-Path $root '.qitesxmlloader-root'))) {
 $marker = $Operation.NewFile((Join-Path $root '.qitesxmlloader-root'))
 $marker.Dispose()
}
function Get-AndroidName([string]$Name) {
 $value = $Name.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
 # Keep Unicode letters, numbers and combining marks. Fold all separators/symbols.
 $value = [regex]::Replace($value, '[^\p{L}\p{Nd}\p{M}]+', '_').Trim('_')
 if (-not $value) { $value = 'unnamed' }
 if ($value -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { $value = 'name_' + $value }
 # Bound UTF-8 component bytes, preserving surrogate pairs.
 $result = ''
 $enumerator = [Globalization.StringInfo]::GetTextElementEnumerator($value)
 while ($enumerator.MoveNext()) {
  $candidate = $result + $enumerator.GetTextElement()
  if ([Text.Encoding]::UTF8.GetByteCount($candidate) -gt 72) { break }
  $result = $candidate
 }
 if (-not $result) { return 'unnamed' }
 return $result
}
$byId = @{}
foreach ($list in $lists) {
 if ($list.Id -notmatch '^[0-9A-Fa-f]{16}$' -or $byId.ContainsKey($list.Id)) { throw (T 'プレイリストIDが不正または重複しています。') }
 $byId[$list.Id] = $list
}
function Get-ListRelativePath($list, $seen) {
 if ($seen -contains $list.Id) { throw (T 'プレイリスト階層が循環しています。') }
 $leaf = (Get-AndroidName $list.Name) + '_' + $list.Id.ToLowerInvariant()
 if ($list.ParentId) {
  if (-not $byId.ContainsKey($list.ParentId) -or -not $byId[$list.ParentId].IsFolder) { throw (T '親フォルダが見つかりません。') }
  return Join-Path (Get-ListRelativePath $byId[$list.ParentId] @($seen + $list.Id)) $leaf
 }
 return $leaf
}
$entries = New-Object 'System.Collections.Generic.List[object]'
$newLinks = New-Object 'System.Collections.Generic.List[object]'
$active = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$totalTracks=0; foreach($list in $lists){$totalTracks+=$list.Tracks.Count};$doneTracks=0
foreach ($list in $lists) {
 $Operation.Check()
 $folder = Join-Path $root (Get-ListRelativePath $list @())
 # Check all existing descendants as well as destination ancestors.
 $check = $folder
 while ($check.Length -ge $root.Length) {
  if ((Test-Path -LiteralPath $check) -and ((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw (T '管理先に再解析ポイントがあります。') }
  $check = [IO.Path]::GetDirectoryName($check)
 }
 $Operation.MakeDirectory($folder)
 if ($list.IsFolder) { continue }
 $m3u = New-Object 'System.Collections.Generic.List[string]'
 $m3u.Add('#EXTM3U');$numberFormat='D'+[math]::Max(4,([string]$list.Tracks.Count).Length)
 foreach ($track in $list.Tracks) {
  $Operation.Check();$doneTracks++;$Operation.Report((T 'ハードリンク同期'),$doneTracks,$totalTracks,($list.Name+" / "+$track.Title))
  if (-not $track.Available) { $entries.Add([pscustomobject]@{Playlist=$list.Name;Track=$track.Title;Status='Missing'}); continue }
  $source = Get-Item -LiteralPath $track.Path
  $extension = $source.Extension
  if ($extension -notmatch '^\.[a-zA-Z0-9]{1,10}$') { throw (T '対応できない拡張子です。') }
  # A new source version gets a new link; previous links are never deleted.
  $key = $source.FullName + '|' + $source.Length + '|' + $source.LastWriteTimeUtc.Ticks
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)))).Replace('-','') } finally { $sha.Dispose() }
  $name = (([int]$track.Order).ToString($numberFormat)+'-') + (Get-AndroidName ($track.Artist + ' ' + $track.Title)) + '_' + $hash.Substring(0,16).ToLowerInvariant() + $extension.ToLowerInvariant()
  $output = Join-Path $folder $name
  if ($output.Length -gt 240) { throw (T '階層が深すぎます。短い出力先を指定してください。') }
  if (-not (Test-Path -LiteralPath $output)) {
   $Operation.Link($source.FullName,$output)
   $newLinks.Add([pscustomobject]@{Source=$source.FullName;Output=$output})
  } else {
   # Do not reuse a substituted file based only on its name.
   [QitesXmlLoader.Native]::NoRedirect($output)
   if([QitesXmlLoader.Native]::Identity($source.FullName) -ne [QitesXmlLoader.Native]::Identity($output)){throw (T '既存リンクの同一性を確認できません。')}
  }
  [void]$active.Add($output)
  $label = [regex]::Replace(($track.Artist + ' - ' + $track.Title), '[\r\n]', ' ')
  $m3u.Add("#EXTINF:$($track.Seconds),$label")
  $m3u.Add($name)
  $entries.Add([pscustomobject]@{Playlist=$list.Name;Track=$track.Title;Source=$source.FullName;Output=$output;Status='Active'})
 }
 $playlistPath = Join-Path $folder 'playlist.m3u8'
 if ((Test-Path -LiteralPath $playlistPath) -and ((Get-Item -LiteralPath $playlistPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw (T 'M3U8が再解析ポイントです。') }
 # Versioned metadata avoids overwriting a file that could have been hardlinked.
 $version = [guid]::NewGuid().ToString('N')
 $Operation.Check(); $Operation.WriteText((Join-Path $folder ('playlist-' + $version + '.m3u8')), (($m3u.ToArray() -join "`r`n")+"`r`n"))
}
$residual = New-Object 'System.Collections.Generic.List[string]'
$pending = New-Object 'System.Collections.Generic.Stack[string]'; $pending.Push($root)
while($pending.Count){
 $Operation.Check();$dir=$pending.Pop();[QitesXmlLoader.Native]::NoRedirect($dir)
 foreach($item in Get-ChildItem -LiteralPath $dir -Force){
  $Operation.Check();[QitesXmlLoader.Native]::NoRedirect($item.FullName)
  if($item.PSIsContainer){$pending.Push($item.FullName)}
  elseif($item.Name -match '_[a-f0-9]{16}\.' -and -not $active.Contains($item.FullName)){$residual.Add($item.FullName)}
 }
 $Operation.Report((T '残存リンク確認'),0,0,$dir)
}
$report = [pscustomobject]@{Generated=(Get-Date).ToString('o');Entries=$entries.ToArray();Residual=$residual.ToArray();Policy='No link deletions. Latest versioned M3U8 represents current order.'}
Write-UnlinkKit -Root $root -Records $newLinks.ToArray() -Operation $Operation
$reportPath = Join-Path $root ('sync-report-' + [guid]::NewGuid().ToString('N') + '.json')
$Operation.Check();$Operation.WriteText($reportPath,($report | ConvertTo-Json -Depth 8))
$Operation.Report((T '完了'),$totalTracks,$totalTracks,$reportPath)
Write-Output $reportPath
