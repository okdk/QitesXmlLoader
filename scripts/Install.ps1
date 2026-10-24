#Requires -Version 5.1
param([string]$ReceiptPath,[string]$InstallDirectory)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'QitesXmlLoader'
. (Join-Path $source 'Core.ps1')
$target=$InstallDirectory
if(-not $target){$target=Join-Path $env:LOCALAPPDATA ('Programs/QitesXmlLoader-0.9-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
if(-not [IO.Path]::IsPathRooted($target)){throw 'The installation directory must be an absolute path.'}
$target=[IO.Path]::GetFullPath($target)
[QitesXmlLoader.Native]::NoRedirect($target)
if([IO.Directory]::Exists($target) -and @(Get-ChildItem -LiteralPath $target -Force).Count){throw 'Choose a new or empty installation directory.'}
$files=@(Get-ChildItem -LiteralPath $source -File -Recurse)
$total=[long]0;foreach($file in $files){$total+=$file.Length}
$drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($target))
if($drive.AvailableFreeSpace -lt $total){throw 'Not enough space for installation.'}
[IO.Directory]::CreateDirectory($target) | Out-Null
$done=[long]0
foreach($file in $files){
 $relative=$file.FullName.Substring($source.Length).TrimStart('\','/')
 $output=Join-Path $target $relative
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
 [IO.File]::Copy($file.FullName,$output,$false);$done+=$file.Length
 Write-Progress -Activity 'Qites xml loader' -Status "$done / $total bytes : $relative" -PercentComplete ([int](100*$done/[math]::Max(1,$total)))
}
$shell=New-Object -ComObject WScript.Shell
$shortcutPath=Join-Path ([Environment]::GetFolderPath('Programs')) 'Qites xml loader.lnk'
$shortcut=$shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath=Join-Path $target 'QitesXmlLoader.exe';$shortcut.WorkingDirectory=$target;$shortcut.IconLocation=$shortcut.TargetPath+',0';$shortcut.Save()
$receipt=[pscustomobject]@{Version='0.9';Path=$target;Shortcut=$shortcutPath;Bytes=$total;Installed=(Get-Date).ToString('o');FFmpegBundled=$false}
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'install-receipt.json') -Encoding UTF8
if($ReceiptPath){$receipt | ConvertTo-Json | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}
Write-Output $target
