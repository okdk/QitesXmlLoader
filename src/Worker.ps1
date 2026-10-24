param([string]$AppRoot,[string]$Kind,$Arguments,[QitesXmlLoader.Operation]$Operation,$Result)
$ErrorActionPreference='Stop'
. (Join-Path $AppRoot 'Core.ps1')
$script:CacheRootOverride=$Arguments.CacheRoot
$script:LibraryPaths=@($Arguments['LibraryPaths']);$script:ResolveLibraryNames=[bool]$Arguments['ResolveLibraryNames']
$script:AllowNetworkPaths=[bool]$Arguments['AllowNetworkPaths']
try {
 switch($Kind){
  'Load' { $loaded=Read-QitesSource -LoaderId $Arguments.SourceLoader -Path $Arguments.Path -Operation $Operation;$Result.Data=@($loaded.Lists);$Result.XmlPath=$loaded.Path;$Result.Summary=$loaded.Summary }
  'Boot' {
   $cached=[QitesXmlLoader.XmlCache]::Load($Arguments.Path,$Operation)
   $Result.Data=@(Convert-LibraryToLists $cached.Library() $Operation -IncludeFolders -SkipFileCheck)
   $Result.XmlPath=$cached.Path;$Result.Summary=$cached.Summary
  }
  'ValidateCache' { [void](Measure-PlaylistFiles $Arguments.Lists $Operation);$Result.Summary=(T 'キャッシュ内の曲ファイルを再確認しました。') }
  'CheckExport' { [void](Measure-PlaylistFiles $Arguments.Lists $Operation) }
  'CheckSync' { $Result.Data=@(Read-ItunesXml -Path $Arguments.Path -IncludeFolders -Operation $Operation);$Result.XmlPath=$Arguments.Path }
  'Export' { $Result.Path=Export-Playlists -Playlists $Arguments.Lists -Destination $Arguments.Destination -Mode $Arguments.Mode -Encoder $Arguments.Encoder -Options $Arguments.Options -Hierarchy $Arguments.Hierarchy -Extension $Arguments.Extension -Muxer $Arguments.Muxer -Target $Arguments.Target -AsciiNames $Arguments.AsciiNames -MissingPolicy $Arguments.MissingPolicy -Operation $Operation }
  'Sync' { $Result.Path=& (Join-Path $AppRoot 'Sync-Hardlinks.ps1') -XmlPath $Arguments.Path -Destination $Arguments.Destination -MissingPolicy $Arguments.MissingPolicy -UseLibraryNames $Arguments.ResolveLibraryNames -AllowNetwork $script:AllowNetworkPaths -Operation $Operation }
  'Rollback' { $Result.Message=$Operation.Rollback();if(-not $Operation.RollbackComplete){throw $Result.Message} }
 }
 $Result.State='Complete'
} catch {
 $Result.Error=$_.Exception.ToString()
 if($Operation.Cancel -ne 0){
  $Result.State='Cancelled'
  if($Operation.Cancel -eq 2){$Result.Message=$Operation.Rollback()}
  else{$Result.Message=(T '即時中止しました。途中出力を保持しています。必要なら「途中出力を復旧」で取り消せます。')}
 }else{$Result.State='Failed';$Result.Message=$_.Exception.Message}
} finally {
 $Result.FileCheck=$script:LastFileCheck;$Result.LibraryPaths=$script:LibraryPaths
 $Result.Finished=$true
}
