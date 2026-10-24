param([switch]$Interactive,[switch]$Apply,[switch]$Json,[switch]$AllowNetwork)
$ErrorActionPreference='Stop'
if($Json){[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)}
try {
 if($Interactive -and $Apply){throw 'Choose Interactive or Apply, not both.'}
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class QitesUnlinkInfo {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sec,uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [StructLayout(LayoutKind.Sequential)]struct Info{public uint Attr;public System.Runtime.InteropServices.ComTypes.FILETIME Created,Access,Write;public uint Volume,SizeHi,SizeLo,Links,IndexHi,IndexLo;}
 public sealed class Record{public string Id;public uint Links;}
 public static Record Read(string path){using(var handle=CreateFile(path,0,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)){Info i;if(handle.IsInvalid||!GetFileInformationByHandle(handle,out i))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());return new Record{Id=i.Volume.ToString("X8")+":"+i.IndexHi.ToString("X8")+i.IndexLo.ToString("X8"),Links=i.Links};}}
}
'@
 $root=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$prefix=$root.TrimEnd('\')+'\';$network=@{}
 function Check-Path([string]$path){
  $path=[IO.Path]::GetFullPath($path)
  if($path.StartsWith('\\') -and $path -notmatch '^\\\\\?\\[a-zA-Z]:\\'){
   if(-not $AllowNetwork){throw 'Network paths require the explicit -AllowNetwork option.'}
   $networkPath=$path;if($networkPath.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)){$networkPath='\\'+$networkPath.Substring(8)}
   $share=[regex]::Match($networkPath,'^\\\\[^\\]+\\[^\\]+').Value
   if(-not $network.ContainsKey($share)){try{[void][IO.File]::GetAttributes($share);$network[$share]='OK'}catch{$network[$share]=$_.Exception.Message}}
   if($network[$share] -ne 'OK'){throw $network[$share]}
  }
  $ancestor=$path
  while($ancestor){if([IO.File]::Exists($ancestor) -or [IO.Directory]::Exists($ancestor)){if([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint){throw 'A reparse point was found; nothing will be removed at this path.'}};$ancestor=[IO.Path]::GetDirectoryName($ancestor)}
 }
 Check-Path $PSScriptRoot;Check-Path $root
 $manifestPath=Join-Path $PSScriptRoot 'manifest.json';Check-Path $manifestPath
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($manifest.Version -ne 1 -or [QitesUnlinkInfo]::Read($root).Id -ne $manifest.RootIdentity){throw 'The export folder identity does not match the original export.'}
 $seen=@{};$plan=New-Object 'System.Collections.Generic.List[object]'
 function Check-Entry($entry){
  if([IO.Path]::IsPathRooted($entry.RelativePath)){throw 'Absolute output paths are not allowed.'}
  $target=[IO.Path]::GetFullPath((Join-Path $root $entry.RelativePath));$source=[IO.Path]::GetFullPath([string]$entry.Source)
  if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Output escapes the export folder.'}
  if($source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $source.Equals($target,[StringComparison]::OrdinalIgnoreCase)){throw 'A source inside the export folder is not eligible for automatic unlinking.'}
  Check-Path $source;Check-Path $target
  if(-not [IO.File]::Exists($source)){throw 'The source is missing.'}
  $sourceInfo=[QitesUnlinkInfo]::Read($source)
  if($sourceInfo.Id -ne $entry.Identity){throw 'The source has been replaced.'}
  if(-not [IO.File]::Exists($target)){return $null}
  $targetInfo=[QitesUnlinkInfo]::Read($target)
  if($targetInfo.Id -ne $entry.Identity){throw 'The generated link has been replaced.'}
  if($targetInfo.Links -lt 2){throw 'Fewer than two links remain; unlinking is blocked.'}
  return $target
 }
 foreach($entry in $manifest.Entries){
  $errorText='';$target=''
  try{if($seen.ContainsKey($entry.RelativePath)){throw 'Duplicate output entry.'};$seen[$entry.RelativePath]=$true;$target=Check-Entry $entry}catch{$errorText=$_.Exception.Message}
  $plan.Add([pscustomobject]@{RelativePath=$entry.RelativePath;Target=$target;AlreadyRemoved=((-not $errorText) -and -not $target);Eligible=(-not $errorText);Error=$errorText})
 }
 $blocked=@($plan | Where-Object {-not $_.Eligible}).Count
 if(-not $Json){$plan | Select-Object RelativePath,AlreadyRemoved,Eligible,Error | Format-Table -AutoSize | Out-Host;Write-Host ('Generated links: '+$plan.Count+'; blocked: '+$blocked);Write-Host 'Only generated directory entries are removed. Original source paths are never deleted.'}
 if($Interactive){
  if($blocked -gt 0){throw 'Validation failed. No links were removed.'}
  $Apply=(Read-Host 'Type UNLINK to remove these generated links, or press Enter to leave them') -ceq 'UNLINK'
 }
 if(-not $Apply){if($Json){[Console]::WriteLine((@{Mode='Preview';Count=$plan.Count;Blocked=$blocked;Entries=$plan.ToArray()} | ConvertTo-Json -Compress -Depth 5))};exit 0}
 if($blocked -gt 0){throw 'Validation failed. No links were removed.'}
 $removed=New-Object 'System.Collections.Generic.List[string]'
 function Remove-GeneratedLink([string]$Target){[IO.File]::Delete($Target)}
 function Apply-UnlinkEntries($Entries,$Removed){foreach($entry in $Entries){$target=Check-Entry $entry;if($target){Remove-GeneratedLink $target;$Removed.Add($entry.RelativePath)}}}
 try{
  Apply-UnlinkEntries $manifest.Entries $removed
 }finally{
  $report=@{Removed=$removed.ToArray();Time=[datetime]::UtcNow.ToString('o')}
  $reportPath=Join-Path $PSScriptRoot ('unlink-result-'+[guid]::NewGuid().ToString('N')+'.json')
  $file=[IO.File]::Open($reportPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report | ConvertTo-Json -Depth 5));$file.Write($bytes,0,$bytes.Length)}finally{$file.Dispose()}
 }
 if($Json){[Console]::WriteLine((@{Mode='Applied';Removed=$removed.Count} | ConvertTo-Json -Compress))}else{Write-Host ('Removed generated links: '+$removed.Count)}
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 2}
