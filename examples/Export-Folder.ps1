param([Parameter(Mandatory)][string]$Source,[string]$Destination,[string]$Program=(Join-Path (Split-Path $PSScriptRoot -Parent) 'QitesXmlLoader.exe'),[ValidateSet('Ignore','Approve')][string]$Policy='Ignore')
$ErrorActionPreference='Stop'
if(-not $Destination){$Destination=Join-Path $PSScriptRoot 'output'}
$Source=[IO.Path]::GetFullPath($Source);$Destination=[IO.Path]::GetFullPath($Destination)
if(-not [IO.File]::Exists($Program)){throw 'QitesXmlLoader.exe not found. Use this example inside the installed or portable application folder, or specify -Program.'}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$Program;$info.Arguments=$(if($Policy -eq 'Approve'){'--pipe --approve-errors'}else{'--pipe --ignore-errors'})
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false);$info.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
$process=New-Object Diagnostics.Process;$process.StartInfo=$info;$started=$false
try{
 [void]$process.Start();$started=$true;$stderr=$process.StandardError.ReadToEndAsync()
 $ready=$process.StandardOutput.ReadLine() | ConvertFrom-Json;if($ready.type -ne 'ready'){throw 'The command interface did not become ready.'}
 function Send-Command([int]$id,[string]$command,$arguments){
  $request=@{id=$id;command=$command;args=$arguments} | ConvertTo-Json -Compress -Depth 8
  $bytes=[Text.Encoding]::UTF8.GetBytes($request+"`n");$process.StandardInput.BaseStream.Write($bytes,0,$bytes.Length);$process.StandardInput.BaseStream.Flush()
  while($null -ne ($line=$process.StandardOutput.ReadLine())){
   $event=$line | ConvertFrom-Json
   if($event.type -eq 'progress'){Write-Host ($event.data.stage+' '+$event.data.done+'/'+$event.data.total)}
   if($event.type -eq 'result' -and $event.id -eq $id){if(-not $event.data.ok){throw ($event.data | ConvertTo-Json -Compress -Depth 8)};if($event.data.PSObject.Properties.Name -contains 'value'){return $event.data.value};return $event.data}
  }
  throw ('The process closed before a result: '+$stderr.GetAwaiter().GetResult())
 }
 [void](Send-Command 1 'configure' @{SourceLoader='single-folder'})
 [void](Send-Command 2 'load' @{path=$Source})
 [void](Send-Command 3 'select' @{all=$true})
 $result=Send-Command 4 'export' @{destination=$Destination;mode='Copy';target='MusicBee'}
 Write-Host ('Output: '+$result.output)
 [void](Send-Command 5 'shutdown' @{})
 $process.StandardInput.Close();$process.WaitForExit()
 if($process.ExitCode -ne 0){throw $stderr.GetAwaiter().GetResult()}
}finally{
 if($started -and -not $process.HasExited){$process.StandardInput.Close();if(-not $process.WaitForExit(15000)){$process.Kill()}}
 $process.Dispose()
}
