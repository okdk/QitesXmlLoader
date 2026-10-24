param([string]$AppRoot)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $AppRoot){$AppRoot=(Get-Content (Join-Path $root 'build/latest.json') -Raw | ConvertFrom-Json).AppRoot}
. (Join-Path $AppRoot 'Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$case=Join-Path $root ('test-output/unlink-'+[guid]::NewGuid().ToString('N').Substring(0,8));[IO.Directory]::CreateDirectory($case) | Out-Null
$source=Join-Path $case 'source.wav';Copy-Item (Join-Path $AppRoot 'startup.wav') $source
$hash=(Get-FileHash $source).Hash
$track=[pscustomobject]@{PlaylistId='1111111111111111';PlaylistName='Test';Order=1;Id='1';Title='Generated';Artist='';Seconds=2;Path=$source;Available=$true;Bytes=0L;Format='WAV'}
$lists=@([pscustomobject]@{Name='Test';Tracks=@($track)})
$operation=New-Object QitesXmlLoader.Operation
$output=Export-Playlists $lists (Join-Path $case 'export') -Mode Hardlink -Operation $operation
$kits=@(Get-ChildItem $output -Directory -Filter 'unlink-*');Assert ($kits.Count -eq 1) 'Unlink kit missing'
Assert (@(Get-ChildItem $output -Filter 'UNLINK-*.bat').Count -eq 1) 'Unlink BAT missing'
$helper=Join-Path $kits[0].FullName 'Unlink-Hardlinks.ps1';$manifestPath=Join-Path $kits[0].FullName 'manifest.json';$originalManifest=[IO.File]::ReadAllText($manifestPath)
function Preview([string]$helperPath){
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName='powershell.exe';$info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$helperPath+'" -Json';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
 $process=[Diagnostics.Process]::Start($info);$errorTask=$process.StandardError.ReadToEndAsync();$text=$process.StandardOutput.ReadToEnd();$process.WaitForExit()
 $result=[pscustomobject]@{ExitCode=$process.ExitCode;Text=$text;Error=$errorTask.GetAwaiter().GetResult()};$process.Dispose();return $result
}
$preview=Preview $helper;Assert ($preview.ExitCode -eq 0) ('Preview failed: '+$preview.Error)
$result=$preview.Text | ConvertFrom-Json;Assert ($result.Mode -eq 'Preview' -and $result.Count -eq 1 -and $result.Blocked -eq 0) 'Valid link was rejected'
Assert ([IO.File]::Exists($source) -and @(Get-ChildItem $output -Recurse -Filter *.wav).Count -eq 1) 'Preview removed audio'
$manifest=$originalManifest | ConvertFrom-Json;$manifest.Entries[0].RelativePath='../../source.wav';[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 6))
$preview=Preview $helper;$result=$preview.Text | ConvertFrom-Json;Assert ($result.Blocked -eq 1) 'Path traversal was not blocked'
$manifest=$originalManifest | ConvertFrom-Json;$manifest.Entries[0].Source=Join-Path $case 'missing.wav';[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 6))
$preview=Preview $helper;$result=$preview.Text | ConvertFrom-Json;Assert ($result.Blocked -eq 1) 'Missing source was not blocked'
[IO.File]::WriteAllText($manifestPath,$originalManifest)
$copy=Join-Path $case 'copied-export';Copy-Item $output $copy -Recurse
$copiedHelper=Join-Path (Join-Path $copy $kits[0].Name) 'Unlink-Hardlinks.ps1';$preview=Preview $copiedHelper
Assert ($preview.ExitCode -eq 2) 'Copied regular files passed original-folder identity check'
Assert ((Get-FileHash $source).Hash -eq $hash -and @(Get-ChildItem $output -Recurse -Filter *.wav).Count -eq 1) 'Original audio changed'
[void]$operation.Rollback()
Assert ([IO.File]::Exists($source) -and (Get-FileHash $source).Hash -eq $hash) 'Rollback touched source audio'
# Mock the identity and removal engine with ordinary text files, never hard links.
$mockRoot=Join-Path $case 'mock-output';[IO.Directory]::CreateDirectory($mockRoot) | Out-Null
$firstSource=Join-Path $case 'first-source.txt';$secondSource=Join-Path $case 'second-source.txt';[IO.File]::WriteAllText($firstSource,'one');[IO.File]::WriteAllText($secondSource,'two')
$firstTarget=Join-Path $mockRoot 'first.txt';$secondTarget=Join-Path $mockRoot 'second.txt';[IO.File]::WriteAllText($firstTarget,'ordinary mock file');[IO.File]::WriteAllText($secondTarget,'ordinary mock file')
Add-Type -TypeDefinition @'
using System.Collections.Generic;
public static class QitesUnlinkInfo {
 public sealed class Record{public string Id;public uint Links;}
 public static Dictionary<string,Record> Records=new Dictionary<string,Record>();
 public static Record Read(string path){return Records[path];}
}
'@
foreach($item in @(@($firstSource,'one'),@($firstTarget,'one'),@($secondSource,'two'),@($secondTarget,'two'))){$record=New-Object QitesUnlinkInfo+Record;$record.Id=$item[1];$record.Links=2;[QitesUnlinkInfo]::Records[$item[0]]=$record}
$parseErrors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $AppRoot 'Unlink-Hardlinks.ps1'),[ref]$tokens,[ref]$parseErrors)
Assert (-not $parseErrors.Count) 'Unlink helper syntax invalid'
foreach($name in @('Check-Path','Check-Entry','Apply-UnlinkEntries')){$function=$ast.FindAll({param($node);$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object Name -eq $name | Select-Object -First 1;. ([scriptblock]::Create($function.Extent.Text))}
$root=$mockRoot;$prefix=$root.TrimEnd('\')+'\';$AllowNetwork=$false;$network=@{};$script:mockCalls=0;$script:mockBlock=$true
function Remove-GeneratedLink([string]$Target){$script:mockCalls++;if($script:mockBlock -and $script:mockCalls -eq 2){throw 'Mock sharing violation'};[IO.File]::Delete($Target)}
$mockEntries=@([pscustomobject]@{RelativePath='first.txt';Source=$firstSource;Identity='one'},[pscustomobject]@{RelativePath='second.txt';Source=$secondSource;Identity='two'})
$removed=New-Object 'System.Collections.Generic.List[string]';$failed=$false
try{Apply-UnlinkEntries $mockEntries $removed}catch{$failed=$true}
Assert ($failed -and $removed.Count -eq 1 -and -not [IO.File]::Exists($firstTarget) -and [IO.File]::Exists($secondTarget)) 'Mock partial failure not reproduced'
$script:mockBlock=$false;$retried=New-Object 'System.Collections.Generic.List[string]';Apply-UnlinkEntries $mockEntries $retried
Assert ($retried.Count -eq 1 -and -not [IO.File]::Exists($secondTarget) -and [IO.File]::Exists($firstSource) -and [IO.File]::Exists($secondSource)) 'Unlink retry did not skip already removed target'
[pscustomobject]@{Passed=$true;SyntheticOnly=$true;RemovalExecuted=$false;Output=$case} | ConvertTo-Json
