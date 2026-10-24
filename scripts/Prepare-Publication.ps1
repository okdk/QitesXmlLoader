$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$stage=Join-Path $root ('.publication/QitesXmlLoader-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($stage) | Out-Null
$files=New-Object 'System.Collections.Generic.List[string]'
foreach($name in @('README.md','README.en.md','LICENSE','NOTICE.md','THIRD-PARTY.md','.gitignore')){$files.Add((Join-Path $root $name))}
foreach($folder in @('assets','docs','examples','.github')){foreach($file in Get-ChildItem -LiteralPath (Join-Path $root $folder) -File -Recurse){$files.Add($file.FullName)}}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'src') -File -Recurse){
 if($file.Extension -in @('.ps1','.cs','.config') -or $file.Name -in @('startup.wav','NAudio-LICENSE.txt') -or ($file.Directory.Name -eq 'loaders' -and $file.Extension -eq '.json') -or ($file.Directory.Name -eq 'i18n' -and $file.Name -in @('ja.json','en.json'))){$files.Add($file.FullName)}
}
foreach($name in @('Build.ps1','Build-Icon.ps1','Restore-Dependencies.ps1','Prepare-Publication.ps1','Install.ps1','Setup.cs','app.manifest')){$files.Add((Join-Path $PSScriptRoot $name))}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'tests') -File | Where-Object Extension -in @('.ps1','.py')){$files.Add($file.FullName)}
$root=[IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar)
$separator=[string][IO.Path]::DirectorySeparatorChar
foreach($file in $files){
 $file=[IO.Path]::GetFullPath($file)
 if(-not $file.StartsWith($root+$separator,[StringComparison]::OrdinalIgnoreCase)){throw 'Source path escaped the publication root'}
 $relative=$file.Substring($root.Length+1);$output=Join-Path $stage $relative
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
 [IO.File]::Copy($file,$output,$false)
}
$textExtensions=@('.ps1','.cs','.json','.config','.md','.yml','.yaml','.svg','.manifest','.txt')
foreach($file in Get-ChildItem -LiteralPath $stage -File -Recurse){
 if($file.Name -match '^(ffmpeg|ffplay|ffprobe)\.exe$' -or $file.Extension -in @('.cache','.log','.itl','.m4a','.mp3','.flac')){throw ('Disallowed publication payload: '+$file.Name)}
 if($file.Extension -in $textExtensions){
  $text=[IO.File]::ReadAllText($file.FullName)
  $profile=[Environment]::GetFolderPath('UserProfile')
  if(($profile.Length -gt 5 -and $text.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or $text -match 'github_pat_[A-Za-z0-9_]{20,}' -or $text -match 'gh[pousr]_[A-Za-z0-9]{30,}' -or $text -match '-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----'){
   throw ('Possible private data in publication source: '+$file.Name)
  }
 }
}
$dist=Join-Path $root 'dist';[IO.Directory]::CreateDirectory($dist) | Out-Null
$zip=Join-Path $dist 'QitesXmlLoader-0.9-source.zip'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$temporary=$zip+'.'+[guid]::NewGuid().ToString('N')+'.partial'
$archive=[IO.Compression.ZipFile]::Open($temporary,[IO.Compression.ZipArchiveMode]::Create)
try{
 foreach($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force){
  $relative=$file.FullName.Substring($stage.Length+1).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
}finally{$archive.Dispose()}
if([IO.File]::Exists($zip)){[IO.File]::Replace($temporary,$zip,[NullString]::Value)}else{[IO.File]::Move($temporary,$zip)}
$result=[pscustomobject]@{SourceDirectory=$stage;SourceZip=$zip;Files=$files.Count;FFmpegBundled=$false;PrivateRuntimeDataIncluded=$false}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'build/publication.json') -Encoding UTF8
$result | ConvertTo-Json
