function Get-SourceLoaders {
 $directory=Join-Path $PSScriptRoot 'loaders';$seen=@{}
 foreach($file in Get-ChildItem -LiteralPath $directory -Filter *.json -File | Sort-Object Name){
  [QitesXmlLoader.Native]::NoRedirect($file.FullName)
  $manifest=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  if($manifest.Id -notmatch '^[a-z0-9-]+$' -or $seen.ContainsKey($manifest.Id) -or $manifest.Input -notin @('xml','folder') -or $manifest.Script -notmatch '^[a-zA-Z0-9_-]+\.ps1$'){throw (T 'ローダー定義が不正です。')}
  $entry=Join-Path $directory $manifest.Script;[QitesXmlLoader.Native]::NoRedirect($entry)
  if(-not [IO.File]::Exists($entry)){throw (T 'ローダーのスクリプトが見つかりません。')}
  $seen[$manifest.Id]=$true
  $language=[QitesXmlLoader.Text]::Culture;$label=[string]$manifest.Names.$language;if(-not $label){$label=[string]$manifest.Names.en}
  [pscustomobject]@{Id=[string]$manifest.Id;Name=$label;Input=[string]$manifest.Input;Entry=$entry}
 }
}
function Read-QitesSource {
 param([string]$LoaderId='itunes',[Parameter(Mandatory)][string]$Path,[QitesXmlLoader.Operation]$Operation=(New-Object QitesXmlLoader.Operation))
 $loader=Get-SourceLoaders | Where-Object Id -eq $LoaderId | Select-Object -First 1
 if(-not $loader){throw (T '指定したローダーがありません。')}
 Assert-AllowedPath $Path
 $Operation.Check()
 $response=@(& $loader.Entry -Path $Path -Operation $Operation)
 if($response.Count -ne 1){throw (T 'ローダーは1つのライブラリを返す必要があります。')}
 if($response[0].Kind -eq 'ITunesXml'){$lists=@(Read-ItunesXml -Path $response[0].Path -IncludeFolders -Operation $Operation);$summary=$script:LastCacheSummary}
 elseif($response[0].Kind -eq 'Library'){$lists=@(Convert-LibraryToLists $response[0].Library $Operation -IncludeFolders);$summary=T 'ローダーからライブラリを読み込みました。'}
 else{throw (T 'ローダーの返却形式に対応していません。')}
 return [pscustomobject]@{Lists=$lists;LibraryPaths=@($script:LibraryPaths);Summary=$summary;Path=$Path}
}
