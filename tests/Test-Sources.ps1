param([string]$AppRoot)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $AppRoot){$AppRoot=(Get-Content (Join-Path $root 'build/latest.json') -Raw | ConvertFrom-Json).AppRoot}
. (Join-Path $AppRoot 'Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$case=Join-Path $root ('test-output/sources-'+[guid]::NewGuid().ToString('N').Substring(0,8));[IO.Directory]::CreateDirectory($case) | Out-Null
$folder=Join-Path $case 'music';[IO.Directory]::CreateDirectory((Join-Path $folder 'nested')) | Out-Null
Copy-Item (Join-Path $AppRoot 'startup.wav') (Join-Path $folder '02 日本語.wav')
Copy-Item (Join-Path $AppRoot 'startup.wav') (Join-Path $folder '01.wav')
Copy-Item (Join-Path $AppRoot 'startup.wav') (Join-Path $folder 'nested/ignored.wav')
[IO.File]::WriteAllText((Join-Path $folder 'ignore.txt'),'not audio')
$loaders=@(Get-SourceLoaders)
Assert ($loaders.Count -eq 2 -and @($loaders | Where-Object Id -eq 'itunes').Count -eq 1 -and @($loaders | Where-Object Id -eq 'single-folder').Count -eq 1) 'Bundled loaders differ'
$result=Read-QitesSource -LoaderId single-folder -Path $folder
Assert ($result.Lists.Count -eq 1 -and $result.Lists[0].Tracks.Count -eq 2 -and $result.LibraryPaths.Count -eq 2) 'Folder loader recursed or missed audio'
Assert ($result.Lists[0].Tracks[0].Title -eq '01' -and $result.Lists[0].Tracks[1].Title -eq '02 日本語') 'Filename order/title failed'
Assert ($result.Lists[0].Tracks[0].Seconds -gt 0 -and $result.Lists[0].Tracks[1].Available) 'Folder metadata/file check failed'
$rejected=$false;try{[void](Read-QitesSource -LoaderId unknown -Path $folder)}catch{$rejected=$true};Assert $rejected 'Unknown loader executed'
Set-AppLanguage en
Assert ((Get-SourceLoaders | Where-Object Id -eq 'single-folder').Name -eq 'Single folder (sample)') 'Loader name not localized'
$settings=Read-AppSettings (Join-Path $case 'settings.json');$settings.SourceLoader='single-folder';$settings.SourcePath=$folder;Save-AppSettings (Join-Path $case 'settings.json') $settings
$settings=Read-AppSettings (Join-Path $case 'settings.json');Assert ($settings.SourceLoader -eq 'single-folder' -and $settings.SourcePath -eq $folder) 'Source settings not saved'
[pscustomobject]@{Passed=$true;SyntheticOnly=$true;Output=$case} | ConvertTo-Json
