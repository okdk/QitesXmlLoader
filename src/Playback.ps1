function Write-PlaybackEvent($eventName,$detail) {
 $entry=[pscustomobject]@{Time=(Get-Date).ToString('o');Event=$eventName;Detail=$detail}
 Add-Content -LiteralPath (Join-Path $script:logRoot 'playback.jsonl') -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
}
function Shuffle-Tracks([object[]]$items) {
 $copy=@($items)
 for($i=$copy.Count-1;$i -gt 0;$i--){$j=$script:random.Next($i+1);$temp=$copy[$i];$copy[$i]=$copy[$j];$copy[$j]=$temp}
 return $copy
}
function Stop-Playback {
 $script:playing=$false
 if($null -ne $script:player){$script:player.Dispose();$script:player=$null}
 if($null -ne $script:testPlayer){$script:testPlayer.Dispose();$script:testPlayer=$null}
 $script:audioPaused=$false;$ui.PauseAudio.Content=(T '一時停止')
 $script:currentTrack=$null;$script:lastPosition=0
 if($ui.ContainsKey('MusicSeek')){Update-PlaybackTimeline}
}
function New-AudioPlayer([string]$path,[double]$offset=0,[double]$duration=0){
 Assert-AllowedPath $path
 return New-Object QitesXmlLoader.AudioEngine($path,$script:outputId,$script:encoder,$offset,$duration)
}
function Format-PlaybackTime([double]$seconds){
 $value=[long][math]::Max(0,[math]::Floor($seconds))
 if($value -ge 3600){return '{0}:{1:00}:{2:00}' -f [long][math]::Floor($value/3600),[long][math]::Floor(($value%3600)/60),($value%60)}
 return '{0}:{1:00}' -f [long][math]::Floor($value/60),($value%60)
}
function Update-PlaylistTimeline {
 $script:playlistOffsets=@{};$script:visibleTotal=0.0
 if($script:visiblePlaylist){foreach($track in $script:visiblePlaylist.Tracks){$key=Get-TrackSelectionKey $track;$script:playlistOffsets[$key]=$script:visibleTotal;$script:visibleTotal+=[double]$track.Seconds}}
}
function Update-PlaybackTimeline {
 $position=$script:lastPosition;$duration=0.0
 if($script:currentTrack){$duration=[double]$script:currentTrack.Seconds}
 if($script:player){$position=$script:player.PositionSeconds;if($script:player.DurationSeconds -gt 0){$duration=$script:player.DurationSeconds};$script:lastPosition=$position}
 $ui.TrackElapsed.Text=Format-PlaybackTime $position;$ui.TrackTotal.Text=' / '+(Format-PlaybackTime $duration)
 $ui.MusicSeek.IsEnabled=($null -ne $script:player -and -not $script:player.Finished -and $duration -gt 0)
 if(-not $script:seeking){$ui.MusicSeek.Maximum=[math]::Max(1,$duration);$ui.MusicSeek.Value=[math]::Min($ui.MusicSeek.Maximum,$position)}
 $listPosition='—'
 if($script:currentTrack){$key=Get-TrackSelectionKey $script:currentTrack;if($script:playlistOffsets.ContainsKey($key)){$listPosition=Format-PlaybackTime ($script:playlistOffsets[$key]+$position)}}
 elseif($position -eq 0){$listPosition='0:00'}
 $ui.PlaylistClock.Text=T 'リスト {0} / {1}' @($listPosition;(Format-PlaybackTime $script:visibleTotal))
}
function Seek-CurrentTrack {
 $script:seeking=$false
 if(-not $script:player -or -not $script:currentTrack){return}
 try{
  $position=[double]$ui.MusicSeek.Value;$paused=$script:audioPaused
  $script:player.Dispose();$script:player=New-AudioPlayer $script:currentTrack.Path $position $script:currentTrack.Seconds
  if($paused){$script:player.SetPaused($true)}
  $script:lastPosition=$position;Write-PlaybackEvent 'Seek' @{Seconds=$position;Paused=$paused};Update-PlaybackTimeline
 }catch{$ui.AudioStatus.Text=$_.Exception.Message;Write-PlaybackEvent 'SeekError' $_.Exception.Message}
}
function Start-NextTrack {
 if(-not $script:playing){return}
 if($script:queueIndex -ge $script:queue.Count){
  if($script:playMode -notin @(1,3)){$script:playing=$false;$ui.AudioStatus.Text=(T '再生終了');Write-PlaybackEvent 'QueueEnded' '';return}
  $script:queue=@($script:queueSource)
  if($script:playMode -eq 3){$script:queue=@(Shuffle-Tracks $script:queue)}
  $script:queueIndex=0;Write-PlaybackEvent 'Loop' $script:playMode
 }
 $track=$script:queue[$script:queueIndex];$script:queueIndex++;$script:currentTrack=$track
 $script:lastPosition=0;$script:player=New-AudioPlayer $track.Path 0 $track.Seconds
 $ui.AudioStatus.Text=(T '再生中 {0} / {1} : {2}' @($script:queueIndex;$($script:queue.Count);$($track.Title)))
 Write-PlaybackEvent 'TrackStarted' @{Path=$track.Path;Title=$track.Title;Index=$script:queueIndex;Mode=$script:playMode;RequestedDevice=$script:outputId}
}
function Start-Playback {
 try {
  Stop-Playback
  if($ui.PlayScope.SelectedIndex -eq 0){$items=@($script:selectedTracks.Values)}
  else{$list=$ui.Playlists.SelectedItem;if($null -eq $list){$list=$script:visiblePlaylist};if($null -eq $list){throw (T 'プレイリストを選んでください。')};$items=@($list.Tracks)}
  $items=@($items | Where-Object {$null -ne $_ -and $_.Available})
  if(-not $items.Count){throw (T '曲一覧の行、または再生可能なプレイリストを選んでください。')}
  $script:queueSource=$items;$script:queue=@($items);$script:playMode=$ui.PlayMode.SelectedIndex
  if($script:playMode -in @(2,3)){$script:queue=@(Shuffle-Tracks $script:queue)}
  $script:queueIndex=0;$script:playing=$true;Start-NextTrack
 }catch{$ui.AudioStatus.Text=$_.Exception.Message;Write-PlaybackEvent 'Error' $_.Exception.Message}
}
function Play-TestSound([string]$eventName){
 Stop-Playback;$script:testPlayer=New-AudioPlayer (Join-Path $PSScriptRoot 'startup.wav')
 $ui.AudioStatus.Text=(T '出力テスト音を再生');Write-PlaybackEvent $eventName @{RequestedDevice=$script:outputId}
}
function Refresh-OutputDevices {
 $script:refreshingDevices=$true
 try{
  $devices=@([QitesXmlLoader.AudioEngine]::Devices());$ui.OutputDevice.ItemsSource=$devices
  $found=@($devices | Where-Object {$_.Id -eq $script:savedOutputId})
  if($found.Count){$ui.OutputDevice.SelectedItem=$found[0];$script:outputId=$script:savedOutputId;$ui.DeviceStatus.Text=(T '出力先: ')+$found[0].Name}
  else{$ui.OutputDevice.SelectedIndex=0;$script:outputId='';$ui.DeviceStatus.Text=(T '保存したデバイスは未接続です。Windowsの既定デバイスを使用します。');Write-PlaybackEvent 'MissingSavedDevice' $script:savedOutputId}
 }catch{$script:outputId='';$ui.DeviceStatus.Text=(T '出力先を列挙できません。既定デバイスを使用します。');Write-PlaybackEvent 'DeviceError' $_.Exception.Message}
 finally{$script:refreshingDevices=$false}
}
$script:savedOutputId=$script:settings.OutputDeviceId;$script:outputId='';$script:refreshingDevices=$false
$script:random=New-Object Random
$script:player=$null;$script:testPlayer=$null;$script:playing=$false;$script:audioPaused=$false
$script:lastPosition=0.0;$script:seeking=$false;$script:playlistOffsets=@{};$script:visibleTotal=0.0
$ui.MusicSeek.IsMoveToPointEnabled=$true
$ui.MusicSeek.Add_PreviewMouseLeftButtonDown({$script:seeking=$true})
$ui.MusicSeek.Add_PreviewMouseLeftButtonUp({Seek-CurrentTrack})
$ui.MusicSeek.Add_LostMouseCapture({if($script:seeking){Seek-CurrentTrack}})
$ui.MusicSeek.Add_KeyUp({param($sender,$eventArgs);if($eventArgs.Key -in @('Left','Right','Home','End','PageUp','PageDown')){Seek-CurrentTrack}})
$ui.PlaybackStrip.Add_SizeChanged({
 $visibility=if($ui.PlaybackStrip.ActualWidth -ge 880){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
 $ui.TrackTotal.Visibility=$visibility;$ui.PlaylistClock.Visibility=$visibility
})
Refresh-OutputDevices
$ui.RefreshDevices.Add_Click({Refresh-OutputDevices})
$ui.OutputDevice.Add_SelectionChanged({
 if($script:refreshingDevices -or $null -eq $ui.OutputDevice.SelectedItem){return}
 try{
  $wasPlaying=$script:playing;$current=$script:currentTrack
  Stop-Playback;$script:outputId=[string]$ui.OutputDevice.SelectedItem.Id;$script:savedOutputId=$script:outputId
  $script:settings.OutputDeviceId=$script:savedOutputId;Save-AppSettings $script:settingsPath $script:settings
  $ui.DeviceStatus.Text=(T '出力先を保存: ')+$ui.OutputDevice.SelectedItem.Name
  Write-PlaybackEvent 'OutputDeviceSaved' @{Id=$script:outputId;Name=$ui.OutputDevice.SelectedItem.Name}
  if($wasPlaying -and $current){$script:currentTrack=$current;$script:playing=$true;$script:player=New-AudioPlayer $current.Path 0 $current.Seconds;$ui.AudioStatus.Text=(T '出力先を切替えて現在の曲を先頭から再生')}
 }catch{$ui.DeviceStatus.Text=(T '出力先の保存に失敗: ')+$_.Exception.Message;Write-PlaybackEvent 'DeviceError' $_.Exception.Message}
})
$ui.PlayAudio.Add_Click({Start-Playback})
$ui.PreviewMenu.Add_Click({$ui.PlayScope.SelectedIndex=0;Start-Playback})
$ui.PauseAudio.Add_Click({
 if($null -ne $script:player -and -not $script:player.Finished){
  $script:audioPaused=-not $script:audioPaused;$script:player.SetPaused($script:audioPaused)
  $ui.PauseAudio.Content=$(if($script:audioPaused){(T '再開')}else{(T '一時停止')});$ui.AudioStatus.Text=$(if($script:audioPaused){(T '一時停止中: ')+$script:currentTrack.Title}else{(T '再生再開: ')+$script:currentTrack.Title});Write-PlaybackEvent $(if($script:audioPaused){'Paused'}else{'Resumed'}) ''
 }
})
$ui.StopAudio.Add_Click({Stop-Playback;$ui.AudioStatus.Text=(T '再生停止');Write-PlaybackEvent 'Stopped' ''})
$ui.TestSound.Add_Click({Play-TestSound 'TestSound'})
$script:currentTrack=$null
$script:playbackTimer=New-Object Windows.Threading.DispatcherTimer;$script:playbackTimer.Interval=[TimeSpan]::FromMilliseconds(100)
$script:playbackTimer.Add_Tick({
 try {
  Update-PlaybackTimeline
  if($null -ne $script:testPlayer -and $script:testPlayer.Finished){
   Write-PlaybackEvent 'TestSoundEnded' @{Error=$script:testPlayer.Error;Bytes=$script:testPlayer.DecodedBytes;DeviceId=$script:testPlayer.DeviceId;Device=$script:testPlayer.DeviceName;ExitCode=$script:testPlayer.DecoderExitCode}
   $ui.AudioStatus.Text=$(if($script:testPlayer.Error){(T '出力テストエラー: ')+$script:testPlayer.Error}else{(T '出力テスト完了: ')+$script:testPlayer.DeviceName})
   $script:testPlayer.Dispose();$script:testPlayer=$null
  }
  if($null -ne $script:player -and $script:player.Finished){
   $errorText=$script:player.Error
   Write-PlaybackEvent 'TrackEnded' @{ExitCode=$script:player.DecoderExitCode;Error=$errorText;Bytes=$script:player.DecodedBytes;DeviceId=$script:player.DeviceId;Device=$script:player.DeviceName}
   $script:player.Dispose();$script:player=$null
   if($errorText){$script:playing=$false;$ui.AudioStatus.Text=(T '再生エラー: ')+$errorText;return}
   Start-NextTrack
  }
 }catch{$ui.AudioStatus.Text=(T '再生エラー: ')+$_.Exception.Message;$script:playing=$false}
})
$script:playbackTimer.Start()
