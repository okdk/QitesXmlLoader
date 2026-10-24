# JSON Lines automation protocol. No UI, shell commands, or source write-back.
param([ValidateSet('stop','reject','approve')][string]$ErrorDecision='stop')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
Set-AppLanguage en
$config=@{SourceLoader='itunes';MissingPolicy='Stop';ResolveLibraryNames=$false;AllowNetworkPaths=$false;ErrorDecision=$ErrorDecision;FFmpegPath='';OutputDeviceId='';Language='en';CacheDirectory=(Join-Path $env:LOCALAPPDATA 'QitesXmlLoader/Cache')}
if($ErrorDecision -eq 'reject'){$config.MissingPolicy='Skip'}
elseif($ErrorDecision -eq 'approve'){$config.MissingPolicy='Skip';$config.ResolveLibraryNames=$true;$config.AllowNetworkPaths=$true}
$script:AllowNetworkPaths=$config.AllowNetworkPaths
$pipeLists=@();$pipePaths=@();$selected=[ordered]@{};$job=$null;$lastOperation=$null;$lastCheck=$null;$closing=$false;$eof=$false
$audio=$null;$audioQueue=@();$audioSource=@();$audioIndex=0;$audioMode='normal';$audioTrack=$null;$audioPaused=$false;$random=New-Object Random
function Field($object,[string]$name,$default=$null){if($null -ne $object){$property=$object.PSObject.Properties[$name];if($null -ne $property){return $property.Value}};return $default}
function Emit([string]$type,$id,$data){[Console]::Out.WriteLine((@{type=$type;id=$id;data=$data} | ConvertTo-Json -Compress -Depth 12));[Console]::Out.Flush()}
function Reply($id,$data){Emit 'result' $id @{ok=$true;value=$data}}
function Fail($id,[string]$code,[string]$message){Emit 'result' $id @{ok=$false;code=$code;message=$message}}
function Track-Key($track){return [string]$track.PlaylistId+'|'+[string]$track.Order}
function Choose-Tracks($arguments){
 $result=[ordered]@{};$ids=@(Field $arguments 'playlistIds' @());$refs=@(Field $arguments 'trackRefs' @());$all=[bool](Field $arguments 'all' $false)
 foreach($list in $script:pipeLists){
  $include=$all -or $list.Id -in $ids;$parent=$list.ParentId;$seen=@($list.Id)
  while(-not $include -and $parent){if($parent -in $seen){throw 'Cyclic playlist hierarchy.'};$seen+=$parent;if($parent -in $ids){$include=$true;break};$entry=$script:pipeLists | Where-Object Id -eq $parent | Select-Object -First 1;if(-not $entry){break};$parent=$entry.ParentId}
  if($include){foreach($track in $list.Tracks){$result[(Track-Key $track)]=$track}}
 }
 foreach($reference in $refs){
  $found=@($script:pipeLists | Where-Object Id -eq ([string](Field $reference 'playlistId')) | ForEach-Object Tracks | Where-Object Order -eq ([int](Field $reference 'order' -1)))
  if($found.Count -ne 1){throw 'A track reference did not identify exactly one row.'};$result[(Track-Key $found[0])]=$found[0]
 }
 if(-not $all -and -not $ids.Count -and -not $refs.Count){foreach($key in $script:selected.Keys){$result[$key]=$script:selected[$key]}}
 return ,$result
}
function Selected-Lists($arguments){
 $chosen=Choose-Tracks $arguments
 if(-not $chosen.Count){throw 'Select at least one track or playlist.'}
 return @(foreach($list in $script:pipeLists){$copy=$list.PSObject.Copy();$copy.Tracks=@($list.Tracks | Where-Object {$chosen.Contains((Track-Key $_))});if($copy.Tracks.Count){$copy}})
}
function Check-Summary($report){
 if($null -eq $report){return $null}
 return @{total=$report.Total;missing=$report.Missing;errors=$report.Errors;ambiguous=$report.Ambiguous;resolved=$report.Resolved;unresolved=$report.Unresolved;missingFiles=$report.MissingFiles;errorFiles=$report.ErrorFiles;ambiguousFiles=$report.AmbiguousFiles;resolvedFiles=$report.ResolvedFiles;issuesTotal=$report.Issues.Count;issues=@($report.Issues | Select-Object -First 20)}
}
function Start-PipeJob([string]$kind,$arguments,$id,$existing=$null){
 $operation=$existing;if($null -eq $operation){$operation=New-Object QitesXmlLoader.Operation}
 $operation.Cancel=0;$operation.PauseRequested=$false
 $arguments.CacheRoot=$script:config.CacheDirectory;$arguments.SourceLoader=$script:config.SourceLoader
 $arguments.LibraryPaths=$script:pipePaths;$arguments.ResolveLibraryNames=$script:config.ResolveLibraryNames;$arguments.MissingPolicy=$script:config.MissingPolicy;$arguments.AllowNetworkPaths=$script:config.AllowNetworkPaths
 $result=[hashtable]::Synchronized(@{State='Running';Message='';Error='';Data=$null;Path='';XmlPath='';Summary='';Finished=$false;FileCheck=$null;LibraryPaths=@()})
 $ps=[PowerShell]::Create();$ps.Runspace=[RunspaceFactory]::CreateRunspace();$ps.Runspace.Open()
 [void]$ps.AddCommand((Join-Path $PSScriptRoot 'Worker.ps1')).AddParameter('AppRoot',$PSScriptRoot).AddParameter('Kind',$kind).AddParameter('Arguments',$arguments).AddParameter('Operation',$operation).AddParameter('Result',$result)
 $script:job=@{Id=$id;Kind=$kind;PS=$ps;Operation=$operation;Result=$result;Handle=$ps.BeginInvoke();Previous=''}
 Emit 'accepted' $id @{operation=$kind}
}
function Stop-PipeAudio {if($script:audio){$script:audio.Dispose();$script:audio=$null};$script:audioQueue=@();$script:audioTrack=$null;$script:audioPaused=$false}
function Shuffle-Pipe([object[]]$tracks){$copy=@($tracks);for($i=$copy.Count-1;$i -gt 0;$i--){$j=$script:random.Next($i+1);$value=$copy[$i];$copy[$i]=$copy[$j];$copy[$j]=$value};return $copy}
function Next-PipeAudio {
 if($script:audioIndex -ge $script:audioQueue.Count){
  if($script:audioMode -notin @('loop','random-loop')){Stop-PipeAudio;Emit 'audio' $null @{state='finished'};return}
  $script:audioQueue=@($script:audioSource);if($script:audioMode -eq 'random-loop'){$script:audioQueue=@(Shuffle-Pipe $script:audioQueue)};$script:audioIndex=0
 }
 $script:audioTrack=$script:audioQueue[$script:audioIndex];$script:audioIndex++
 Assert-AllowedPath $script:audioTrack.Path ([bool]$script:config.AllowNetworkPaths)
 $script:audio=New-Object QitesXmlLoader.AudioEngine($script:audioTrack.Path,$script:config.OutputDeviceId,(Resolve-FFmpeg $script:config.FFmpegPath),0.0,[double]$script:audioTrack.Seconds)
 Emit 'audio' $null @{state='playing';playlistId=$script:audioTrack.PlaylistId;order=$script:audioTrack.Order;index=$script:audioIndex;count=$script:audioQueue.Count}
}
$utf8=New-Object Text.UTF8Encoding($false)
$reader=New-Object IO.StreamReader([Console]::OpenStandardInput(),$utf8,$true,4096,$true)
$writer=New-Object IO.StreamWriter([Console]::OpenStandardOutput(),$utf8,4096,$true);$writer.AutoFlush=$true;[Console]::SetOut($writer)
Emit 'ready' $null @{protocol='qites-jsonl';version=1;appVersion='0.9'}
$inputTask=$reader.ReadLineAsync();$lastAudioEvent=[datetime]::MinValue
try {
 while(-not $closing -or $job){
  if(-not $closing -and $inputTask.IsCompleted){
   $line=$inputTask.GetAwaiter().GetResult()
   if($null -eq $line){$eof=$true;$closing=$true;Stop-PipeAudio;if($job -and $job.Operation.PauseRequested){$job.Operation.Cancel=1;$job.Operation.PauseRequested=$false}}
   else{
    $id=$null
    try{
     if($line.Length -gt 1048576){throw 'Command exceeds the 1 MiB limit.'}
     $request=$line | ConvertFrom-Json
     if($request -isnot [pscustomobject]){throw 'A request must be a JSON object.'}
     $id=Field $request 'id'
     if($null -ne $id -and $id -isnot [string] -and $id -isnot [int] -and $id -isnot [long]){$id=$null;throw 'An ID must be a string, integer, or null.'}
     if($id -is [string] -and $id.Length -gt 128){$id=$null;throw 'An ID cannot exceed 128 characters.'}
     $command=[string](Field $request 'command' '');$arguments=Field $request 'args' ([pscustomobject]@{})
     if($arguments -isnot [pscustomobject]){throw 'args must be a JSON object.'}
     if($job -and $command -notin @('pause','resume','cancel','status','shutdown')){Fail $id 'busy' 'An operation is already running.'}
     else{switch($command){
      'sources' {Reply $id @(Get-SourceLoaders | Select-Object Id,Name,Input)}
      'formats' {Reply $id @(Get-OutputFormats)}
      'devices' {Reply $id @([QitesXmlLoader.AudioEngine]::Devices())}
      'network.status' {Reply $id @([QitesXmlLoader.NetworkMemory]::List())}
      'network.reset' {[QitesXmlLoader.NetworkMemory]::Reset();Reply $id @{reset=$true}}
      'configure' {
       $next=$script:config.Clone()
       if((Field $arguments 'ErrorDecision') -eq 'stop'){$next.MissingPolicy='Stop';$next.ResolveLibraryNames=$false;$next.AllowNetworkPaths=$false}
       foreach($name in @('SourceLoader','MissingPolicy','ResolveLibraryNames','AllowNetworkPaths','ErrorDecision','FFmpegPath','OutputDeviceId','Language','CacheDirectory')){if($null -ne $arguments.PSObject.Properties[$name]){$next[$name]=$arguments.$name}}
       if($next.ErrorDecision -notin @('stop','reject','approve')){throw 'Unknown ErrorDecision.'}
       if($next.ErrorDecision -eq 'reject'){$next.MissingPolicy='Skip';$next.ResolveLibraryNames=$false;$next.AllowNetworkPaths=$false}
       elseif($next.ErrorDecision -eq 'approve'){$next.MissingPolicy='Skip';$next.ResolveLibraryNames=$true;$next.AllowNetworkPaths=$true}
       if($next.MissingPolicy -notin @('Stop','Skip') -or $next.Language -notin @('ja','en') -or $next.ResolveLibraryNames -isnot [bool] -or $next.AllowNetworkPaths -isnot [bool]){throw 'Invalid configuration value.'}
       if(-not (Get-SourceLoaders | Where-Object Id -eq $next.SourceLoader)){throw 'Unknown source loader.'}
       if(-not [IO.Path]::IsPathRooted($next.CacheDirectory)){throw 'CacheDirectory must be absolute.'}
       if($next.SourceLoader -ne $script:config.SourceLoader){Stop-PipeAudio;$script:pipeLists=@();$script:pipePaths=@();$script:selected=[ordered]@{}}
       $script:config=$next;$script:AllowNetworkPaths=[bool]$next.AllowNetworkPaths;Set-AppLanguage $next.Language;Reply $id $script:config
      }
      'load' {Stop-PipeAudio;Start-PipeJob 'Load' @{Path=[string](Field $arguments 'path' '')} $id}
      'lists' {Reply $id @($script:pipeLists | ForEach-Object {@{id=$_.Id;name=$_.Name;parentId=$_.ParentId;folder=$_.IsFolder;smart=$_.IsSmart;tracks=$_.Tracks.Count}})}
      'tracks' {
       $playlistId=[string](Field $arguments 'playlistId' '');$offset=[math]::Max(0,[int](Field $arguments 'offset' 0));$limit=[math]::Min(1000,[math]::Max(1,[int](Field $arguments 'limit' 100)))
       $tracks=@($script:pipeLists | Where-Object {(-not $playlistId) -or $_.Id -eq $playlistId} | ForEach-Object Tracks)
       Reply $id @{total=$tracks.Count;offset=$offset;items=@($tracks | Select-Object -Skip $offset -First $limit)}
      }
      'select' {$script:selected=Choose-Tracks $arguments;Reply $id @{selected=$script:selected.Count}}
      'clearSelection' {$script:selected=[ordered]@{};Reply $id @{selected=0}}
      'check' {Stop-PipeAudio;Start-PipeJob 'ValidateCache' @{Lists=$script:pipeLists} $id}
      'issues' {$offset=[math]::Max(0,[int](Field $arguments 'offset' 0));$limit=[math]::Min(1000,[math]::Max(1,[int](Field $arguments 'limit' 100)));Reply $id @{total=$(if($script:lastCheck){$script:lastCheck.Issues.Count}else{0});items=@(if($script:lastCheck){$script:lastCheck.Issues | Select-Object -Skip $offset -First $limit})}}
      'export' {
       $lists=@(Selected-Lists $arguments);$mode=[string](Field $arguments 'mode' 'Copy');$format=Get-OutputFormats | Where-Object Id -eq $mode | Select-Object -First 1;if(-not $format){throw 'Unknown output mode.'}
       Start-PipeJob 'Export' @{Lists=$lists;Destination=[string](Field $arguments 'destination' '');Mode=$mode;Encoder=(Resolve-FFmpeg $script:config.FFmpegPath);Options=[string](Field $arguments 'options' $format.Options);Hierarchy=$script:pipeLists;Extension=[string](Field $arguments 'extension' $format.Extension);Muxer=[string](Field $arguments 'muxer' $format.Muxer);Target=[string](Field $arguments 'target' 'Generic');AsciiNames=[bool](Field $arguments 'asciiNames' $false)} $id
      }
      'sync' {if($script:config.SourceLoader -ne 'itunes'){throw 'Extended sync requires the iTunes XML source.'};Start-PipeJob 'Sync' @{Path=[string](Field $arguments 'path' '');Destination=[string](Field $arguments 'destination' '')} $id}
      'pause' {if(-not $job){throw 'No active operation.'};$job.Operation.PauseRequested=$true;Reply $id @{pauseRequested=$true}}
      'resume' {if(-not $job){throw 'No active operation.'};$job.Operation.PauseRequested=$false;Reply $id @{pauseRequested=$false}}
      'cancel' {if(-not $job){throw 'No active operation.'};$mode=[string](Field $arguments 'mode' 'keep');if($mode -notin @('keep','rollback')){throw 'Cancel mode must be keep or rollback.'};$job.Operation.Cancel=$(if($mode -eq 'rollback'){2}else{1});$job.Operation.PauseRequested=$false;Reply $id @{cancelRequested=$mode}}
      'rollback' {if(-not $lastOperation){throw 'No output operation from this process can be rolled back.'};Start-PipeJob 'Rollback' @{} $id $lastOperation}
      'status' {Reply $id @{busy=($null -ne $job);paused=$(if($job){$job.Operation.Paused}else{$false});audioPosition=$(if($audio){$audio.PositionSeconds}else{0});audioDuration=$(if($audio){$audio.DurationSeconds}else{0})}}
      'audio.play' {
       Stop-PipeAudio;$script:audioMode=[string](Field $arguments 'mode' 'normal');if($script:audioMode -notin @('normal','loop','random','random-loop')){throw 'Unknown playback mode.'}
       $chosen=Choose-Tracks $arguments;$script:audioSource=@($chosen.Values | Where-Object Available);if(-not $script:audioSource.Count){throw 'No accessible selected tracks.'}
       $script:audioQueue=@($script:audioSource);if($script:audioMode -in @('random','random-loop')){$script:audioQueue=@(Shuffle-Pipe $script:audioQueue)};$script:audioIndex=0;Next-PipeAudio;Reply $id @{playing=$true}
      }
      'audio.test' {Stop-PipeAudio;$script:audio=New-Object QitesXmlLoader.AudioEngine((Join-Path $PSScriptRoot 'startup.wav'),$script:config.OutputDeviceId,(Resolve-FFmpeg $script:config.FFmpegPath));Reply $id @{playing=$true}}
      'audio.pause' {if(-not $audio){throw 'No active audio.'};$script:audioPaused=$true;$audio.SetPaused($true);Reply $id @{paused=$true}}
      'audio.resume' {if(-not $audio){throw 'No active audio.'};$script:audioPaused=$false;$audio.SetPaused($false);Reply $id @{paused=$false}}
      'audio.seek' {if(-not $audio -or -not $audioTrack -or $audioTrack.Seconds -le 0){throw 'No seekable track.'};if($null -eq (Field $arguments 'seconds')){throw 'seconds is required.'};$position=[double](Field $arguments 'seconds');if([double]::IsNaN($position) -or [double]::IsInfinity($position) -or $position -lt 0 -or $position -gt $audioTrack.Seconds){throw 'Seek position is outside the track.'};$audio.Dispose();$script:audio=New-Object QitesXmlLoader.AudioEngine($audioTrack.Path,$script:config.OutputDeviceId,(Resolve-FFmpeg $script:config.FFmpegPath),$position,[double]$audioTrack.Seconds);if($audioPaused){$audio.SetPaused($true)};Reply $id @{seconds=$position}}
      'audio.stop' {Stop-PipeAudio;Reply $id @{playing=$false}}
      'shutdown' {$closing=$true;Stop-PipeAudio;if($job){$job.Operation.Cancel=$(if((Field $arguments 'mode' 'keep') -eq 'rollback'){2}else{1});$job.Operation.PauseRequested=$false};Reply $id @{shuttingDown=$true}}
      default {Fail $id 'unknown_command' 'Unknown command.'}
     }}
    }catch{Fail $id 'invalid_request' $_.Exception.Message}
    if(-not $closing){$inputTask=$reader.ReadLineAsync()}
   }
  }
  if($job){
   $snapshot=$job.Operation.Snapshot();$progress=@{stage=$snapshot[0];done=[long]$snapshot[1];total=[long]$snapshot[2];detail=$snapshot[3];paused=$job.Operation.Paused}
   $encoded=$progress | ConvertTo-Json -Compress
   if($encoded -ne $job.Previous){Emit 'progress' $job.Id $progress;$job.Previous=$encoded}
   if($job.Handle.IsCompleted){
    try{[void]$job.PS.EndInvoke($job.Handle)}catch{$job.Result.State='Failed';$job.Result.Message=$_.Exception.Message}
    $job.PS.Runspace.Close();$job.PS.Dispose();$completed=$job;$job=$null;$result=$completed.Result
    if($result.State -eq 'Running'){$result.State='Failed';$result.Message='Worker ended without a result.'}
    if($completed.Operation.Cancel -eq 2 -and $result.State -eq 'Complete' -and $completed.Kind -ne 'Rollback'){$result.Message=$completed.Operation.Rollback();$result.State='Cancelled'}
    elseif($completed.Operation.Cancel -eq 1 -and $result.State -eq 'Complete' -and $completed.Kind -ne 'Rollback'){$result.State='Cancelled'}
    if($completed.Kind -in @('Export','Sync')){$lastOperation=$completed.Operation}
    if(-not $completed.Operation.RollbackComplete){$lastOperation=$completed.Operation}
    if($result.FileCheck){$lastCheck=$result.FileCheck}
    if($result.State -eq 'Complete' -and $completed.Kind -eq 'Load'){$script:pipeLists=@($result.Data);$script:pipePaths=@($result.LibraryPaths);$script:selected=[ordered]@{}}
    if($result.State -eq 'Complete' -and $completed.Kind -eq 'Rollback'){$lastOperation=$null}
    Emit 'result' $completed.Id @{ok=($result.State -eq 'Complete');state=$result.State;message=$result.Message;output=$result.Path;summary=$result.Summary;fileCheck=(Check-Summary $result.FileCheck);playlists=$script:pipeLists.Count}
   }
  }
  if($audio -and $audio.Finished){$errorText=$audio.Error;$audio.Dispose();$audio=$null;if($errorText){Stop-PipeAudio;Emit 'audio' $null @{state='failed';message=$errorText}}elseif($audioQueue.Count){Next-PipeAudio}else{Emit 'audio' $null @{state='finished'}}}
  if($audio -and ([datetime]::UtcNow-$lastAudioEvent).TotalMilliseconds -ge 250){Emit 'audio' $null @{state=$(if($audioPaused){'paused'}else{'playing'});seconds=$audio.PositionSeconds;duration=$audio.DurationSeconds};$lastAudioEvent=[datetime]::UtcNow}
  Start-Sleep -Milliseconds 40
 }
} finally {
 Stop-PipeAudio
 if($job){$job.Operation.Cancel=1;$job.Operation.PauseRequested=$false;try{[void]$job.PS.EndInvoke($job.Handle)}catch{};$job.PS.Runspace.Close();$job.PS.Dispose()}
 $writer.Flush()
}
