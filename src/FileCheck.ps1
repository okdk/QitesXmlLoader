# Only paths registered in the loaded XML are considered. No directory search.
if(-not (Get-Variable LibraryPaths -Scope Script -ErrorAction SilentlyContinue)){$script:LibraryPaths=@()}
if(-not (Get-Variable ResolveLibraryNames -Scope Script -ErrorAction SilentlyContinue)){$script:ResolveLibraryNames=$false}
if(-not (Get-Variable AllowNetworkPaths -Scope Script -ErrorAction SilentlyContinue)){$script:AllowNetworkPaths=$false}
$script:LastFileCheck=$null
function Test-NetworkPath([string]$Path){
 if(-not $Path){return $false}
 $value=$Path.Replace('/','\')
 return $value.StartsWith('\\') -and $value -notmatch '^\\\\\?\\[a-zA-Z]:\\'
}
function Assert-AllowedPath([string]$Path,[bool]$AllowNetwork=$script:AllowNetworkPaths){
 if(-not $AllowNetwork -and (Test-NetworkPath $Path)){throw (T 'ネットワーク参照は無効です。NASなどを使う場合は設定で許可してください。')}
 if($AllowNetwork -and (Test-NetworkPath $Path)){
  $root=Get-NetworkRoot $Path;$known=[QitesXmlLoader.NetworkMemory]::Get($root)
  if($null -eq $known){$state=Get-PhysicalNetworkState $root;[QitesXmlLoader.NetworkMemory]::Set($root,$state.Connected,$state.Error);$known=[QitesXmlLoader.NetworkMemory]::Get($root)}
  if(-not $known.Connected){throw $known.Error}
 }
}
function Get-NetworkRoot([string]$Path){
 $value=$Path.Replace('/','\');if($value.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)){$value='\\'+$value.Substring(8)}
 $match=[regex]::Match($value,'^\\\\[^\\]+\\[^\\]+')
 if(-not $match.Success){throw (T 'ネットワーク共有のパスが不正です。')};return $match.Value
}
function Get-PhysicalNetworkState([string]$Root){
 try{[void][IO.File]::GetAttributes($Root);return [pscustomobject]@{Connected=$true;Error=''}}catch{return [pscustomobject]@{Connected=$false;Error=$_.Exception.Message}}
}
function Get-LibraryLocation($track){
 if(-not $track -or -not $track['Location']){return ''}
 $uri=$null
 if(-not [uri]::TryCreate([string]$track['Location'],[UriKind]::Absolute,[ref]$uri) -or -not $uri.IsFile){return ''}
 if($uri.Host -ieq 'localhost'){$local=[uri]::UnescapeDataString($uri.AbsolutePath);if($local -match '^/?[a-zA-Z]:/'){return $local.TrimStart('/').Replace('/','\')}}
 return $uri.LocalPath
}
function Get-FileCheckState([string]$Path){
 if([string]::IsNullOrWhiteSpace($Path)){return [pscustomobject]@{Exists=$false;Bytes=0L;Error=''}}
 try{Assert-AllowedPath $Path}catch{return [pscustomobject]@{Exists=$false;Bytes=0L;Error=$_.Exception.Message}}
 return Get-PhysicalFileState $Path
}
function Get-PhysicalFileState([string]$Path){
 try{
  $attributes=[IO.File]::GetAttributes($Path)
  if($attributes -band [IO.FileAttributes]::Directory){throw [IO.IOException]::new((T '音声ファイルではなくフォルダを参照しています。'))}
  $length=(New-Object IO.FileInfo($Path)).Length
  return [pscustomobject]@{Exists=$true;Bytes=[long]$length;Error=''}
 }catch{
  $cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException}
  $missing=$cause -is [IO.FileNotFoundException] -or $cause -is [IO.DirectoryNotFoundException]
  if((Test-NetworkPath $Path) -and ($cause.HResult -band 65535) -in @(53,64,67,121,1231,1232,1326,2250)){[QitesXmlLoader.NetworkMemory]::Set((Get-NetworkRoot $Path),$false,$cause.Message)}
  return [pscustomobject]@{Exists=$false;Bytes=0L;Error=$(if($missing){''}else{$cause.Message})}
 }
}
function Measure-PlaylistFiles {
 param([object[]]$Playlists,[QitesXmlLoader.Operation]$Operation)
 $total=0;foreach($list in $Playlists){$total+=$list.Tracks.Count}
 $cache=@{};$missing=@{};$n=0
 foreach($list in $Playlists){foreach($track in $list.Tracks){
  $Operation.Check();$n++;$Operation.Report((T 'ファイル存在・容量確認'),$n,$total,"$($list.Name) / $($track.Title)")
  if($track.PSObject.Properties.Name -notcontains 'OriginalPath'){$track | Add-Member NoteProperty OriginalPath ([string]$track.Path)}
  $path=[string]$track.OriginalPath
  if(-not $cache.ContainsKey($path)){$cache[$path]=Get-FileCheckState $path}
  $state=$cache[$path]
  $track.Path=$path;$track.Available=$state.Exists;$track.Bytes=$state.Bytes
  $track | Add-Member NoteProperty FileStatus $(if($state.Exists){'Found'}elseif($state.Error){'Error'}else{'Missing'}) -Force
  $track | Add-Member NoteProperty FileError ([string]$state.Error) -Force
  if(-not $state.Exists){$missing[$path]=$true}
 }}
 $resolved=@{};$candidateErrors=@{};$ambiguous=@{}
 if($script:ResolveLibraryNames -and $missing.Count){
  $wanted=@{};foreach($path in $missing.Keys){if($path){$name=[IO.Path]::GetFileName($path);if($name){$wanted[$name]=$true}}}
  $candidates=@{};$i=0
  foreach($path in $script:LibraryPaths){
   $Operation.Check();$i++;if($i%64 -eq 0){$Operation.Report((T 'ライブラリ内の同名参照を照合'),$i,$script:LibraryPaths.Count,(T '同名候補を登録済みパスから確認中'))}
   if(-not $path){continue};$name=[IO.Path]::GetFileName($path)
   if($wanted.ContainsKey($name)){
    if(-not $candidates.ContainsKey($name)){$candidates[$name]=@{}}
    $candidates[$name][$path]=$true
   }
  }
  foreach($name in $candidates.Keys){
   $valid=New-Object 'System.Collections.Generic.List[string]';$errors=0;$i=0
   foreach($path in $candidates[$name].Keys){
    $Operation.Check();$i++;$Operation.Report((T '同名候補の存在確認'),$i,$candidates[$name].Count,$path)
    if(-not $cache.ContainsKey($path)){$cache[$path]=Get-FileCheckState $path}
    if($cache[$path].Exists){$valid.Add($path)}elseif($cache[$path].Error){$errors++}
   }
   if($valid.Count -eq 1 -and $errors -eq 0){$resolved[$name]=$valid[0]}
   elseif($valid.Count -ge 2){$ambiguous[$name]=$valid.Count}
   elseif($errors){$candidateErrors[$name]=$errors}
  }
 }
 $bytes=0L;$missingRows=0;$errorRows=0;$ambiguousRows=0;$resolvedRows=0;$issues=New-Object 'System.Collections.Generic.List[object]'
 $uniqueMissing=@{};$uniqueError=@{};$uniqueAmbiguous=@{};$uniqueResolved=@{}
 foreach($list in $Playlists){foreach($track in $list.Tracks){
  $Operation.Check();$original=[string]$track.OriginalPath
  if(-not $track.Available){
   $name=[IO.Path]::GetFileName($original)
   if($resolved.ContainsKey($name)){
    $track.Path=$resolved[$name];$track.Available=$true;$track.Bytes=$cache[$track.Path].Bytes;$track.FileStatus='Resolved';$track.FileError=''
    $resolvedRows++;$uniqueResolved[$original]=$true
   }elseif($ambiguous.ContainsKey($name)){$track.FileStatus='Ambiguous';$ambiguousRows++;$uniqueAmbiguous[$original]=$true}
   elseif($track.FileError -or $candidateErrors.ContainsKey($name)){$track.FileStatus='Error';$errorRows++;$uniqueError[$original]=$true}
   else{$missingRows++;$uniqueMissing[$original]=$true}
   $issues.Add([pscustomobject]@{Title=$track.Title;OriginalPath=$original;ReferencedPath=$track.Path;Status=$track.FileStatus;Error=$track.FileError;ExistingCandidates=$(if($ambiguous.ContainsKey($name)){$ambiguous[$name]}elseif($track.Available){1}else{0})})
  }
  $track.Format=[IO.Path]::GetExtension($track.Path).TrimStart('.').ToUpperInvariant();$bytes+=$track.Bytes
 }}
 $script:LastFileCheck=[pscustomobject]@{Total=$total;Missing=$missingRows;Errors=$errorRows;Ambiguous=$ambiguousRows;Resolved=$resolvedRows;Unresolved=($missingRows+$errorRows+$ambiguousRows);MissingFiles=$uniqueMissing.Count;ErrorFiles=$uniqueError.Count;AmbiguousFiles=$uniqueAmbiguous.Count;ResolvedFiles=$uniqueResolved.Count;Issues=$issues.ToArray()}
 $Operation.Report((T '容量確認完了'),$total,$total,((T '{0} 曲 / 元ファイル合計 {1:N0} bytes（重複含む）') -f $total,$bytes))
 return $bytes
}
function Get-FileCheckMessage($Report){
 return T '確認対象 {0}行：見つからない {1}件、確認エラー {2}件、複数の実在候補 {3}件、別パスを参照 {4}件。\n重複を除くファイル数：未検出 {5}、エラー {6}、候補複数 {7}、参照変更 {8}。' @($Report.Total;$Report.Missing;$Report.Errors;$Report.Ambiguous;$Report.Resolved;$Report.MissingFiles;$Report.ErrorFiles;$Report.AmbiguousFiles;$Report.ResolvedFiles)
}

function Test-AllowedSourceExists([string]$Path,[ValidateSet('file','folder')][string]$Kind='file'){
 try{Assert-AllowedPath $Path}catch{return $false}
 if($Kind -eq 'folder'){return [IO.Directory]::Exists($Path)}
 return [IO.File]::Exists($Path)
}
