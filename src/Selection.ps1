$script:selectedTracks=[ordered]@{}
$script:synchronizingSelection=$false
$script:selectionJob=$null
$script:visiblePlaylist=$null
function Get-TrackSelectionKey($track){
 $playlist=[string]$track.PlaylistId;if(-not $playlist){$playlist=[string]$track.PlaylistName}
 return $playlist+'|'+([string]$track.Order)+'|'+([string]$track.Id)+'|'+($(if($track.PSObject.Properties.Name -contains 'OriginalPath'){[string]$track.OriginalPath}else{[string]$track.Path})).ToUpperInvariant()
}
function Update-SelectionSummary {
 $ui.SelectedTrack.Text=T '選択した曲: {0}曲（Ctrl・Shift・ドラッグで複数選択）' @($script:selectedTracks.Count)
}
function Set-VisiblePlaylist($list){
 if($null -eq $list){return}
 $script:visiblePlaylist=$list
 $script:synchronizingSelection=$true
 try{
  $ui.Tracks.ItemsSource=$list.Tracks;$ui.ListTitle.Text=$list.Name
  $ui.ListSummary.Text=T '{0}曲 · XMLに保存された曲順' @($list.Tracks.Count)
  # Restore only previously selected rows; switching lists never clears the basket.
  foreach($track in $list.Tracks){if($script:selectedTracks.Contains((Get-TrackSelectionKey $track))){$ui.Tracks.SelectedItems.Add($track) | Out-Null}}
 }finally{$script:synchronizingSelection=$false}
 Update-SelectionSummary
 Update-PlaylistTimeline;Update-PlaybackTimeline
 if($list.IsSmart -and -not $list.Tracks.Count){$ui.Status.Text=T 'このスマートプレイリストにはXML上の曲一覧がありません。条件の再評価は行いません。'}
}
$ui.Playlists.Add_SelectedItemChanged({Set-VisiblePlaylist $ui.Playlists.SelectedItem})
$ui.Playlists.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{
 param($sender,$eventArgs)
 if($eventArgs.OriginalSource -is [Windows.Controls.CheckBox] -and $eventArgs.OriginalSource.DataContext -is [QitesXmlLoader.PlaylistNode]){
  $container=$eventArgs.OriginalSource
  while($null -ne $container -and $container -isnot [Windows.Controls.TreeViewItem]){$container=[Windows.Media.VisualTreeHelper]::GetParent($container)}
  if($container){$container.IsSelected=$true}
  Set-VisiblePlaylist $eventArgs.OriginalSource.DataContext
 }
})
$ui.Playlists.Add_PreviewMouseRightButtonDown({param($sender,$eventArgs)
 $container=$eventArgs.OriginalSource
 while($null -ne $container -and $container -isnot [Windows.Controls.TreeViewItem]){
  if($container -is [Windows.Media.Visual]){$container=[Windows.Media.VisualTreeHelper]::GetParent($container)}else{$container=$null}
 }
 if($container -is [Windows.Controls.TreeViewItem]){$container.IsSelected=$true}
})
$ui.Tracks.Add_SelectionChanged({param($sender,$eventArgs)
 if($script:synchronizingSelection){return}
 foreach($track in $eventArgs.RemovedItems){$script:selectedTracks.Remove((Get-TrackSelectionKey $track))}
 foreach($track in $eventArgs.AddedItems){$script:selectedTracks[(Get-TrackSelectionKey $track)]=$track}
 Update-SelectionSummary
})
$ui.ClearSelection.Add_Click({
 $script:synchronizingSelection=$true
 try{$script:selectedTracks.Clear();$ui.Tracks.SelectedItems.Clear()}finally{$script:synchronizingSelection=$false}
 Update-SelectionSummary
})
$ui.AddPlaylistSelection.Add_Click({
 if($script:busy -or $null -eq $ui.Playlists.SelectedItem){return}
 $list=$ui.Playlists.SelectedItem;Set-VisiblePlaylist $list
 $before=[ordered]@{};foreach($entry in $script:selectedTracks.GetEnumerator()){$before[$entry.Key]=$entry.Value}
 $operation=New-Object QitesXmlLoader.Operation
 $script:selectionJob=@{Tracks=@($list.Tracks);Index=0;Before=$before;Operation=$operation}
 Set-Busy $true
 $ui.PauseWork.Content=T '処理を一時停止'
})
$script:selectionTimer=New-Object Windows.Threading.DispatcherTimer
$script:selectionTimer.Interval=[TimeSpan]::FromMilliseconds(20)
$script:selectionTimer.Add_Tick({
 if($null -eq $script:selectionJob){return}
 $job=$script:selectionJob;$operation=$job.Operation
 if($operation.Cancel -ne 0){
  if($operation.Cancel -eq 2){$script:selectedTracks=$job.Before;Set-VisiblePlaylist $ui.Playlists.SelectedItem}
  $script:selectionJob=$null;Set-Busy $false;$ui.Progress.IsIndeterminate=$false
  $ui.Status.Text=$(if($operation.Cancel -eq 2){T '選択を処理開始前へ復旧しました。'}else{T '選択の追加を中止しました。途中の選択は保持しています。'})
  Update-SelectionSummary;return
 }
 if($operation.PauseRequested){$operation.Paused=$true;$ui.Status.Text=T '一時停止中';return}
 $operation.Paused=$false;$script:synchronizingSelection=$true
 try{
  $limit=[math]::Min($job.Tracks.Count,$job.Index+64)
  while($job.Index -lt $limit){$track=$job.Tracks[$job.Index];$key=Get-TrackSelectionKey $track;$script:selectedTracks[$key]=$track;if(-not $ui.Tracks.SelectedItems.Contains($track)){$ui.Tracks.SelectedItems.Add($track) | Out-Null};$job.Index++}
 }finally{$script:synchronizingSelection=$false}
 $ui.Status.Text=T 'プレイリストの曲を選択に追加中'
 $ui.Progress.IsIndeterminate=$false;$ui.Progress.Value=100*$job.Index/[math]::Max(1,$job.Tracks.Count)
 $ui.ProgressDetail.Text=T '{0} / {1}曲' @($job.Index;$job.Tracks.Count)
 Update-SelectionSummary
 if($job.Index -ge $job.Tracks.Count){$script:selectionJob=$null;Set-Busy $false;$ui.Status.Text=T 'プレイリスト全体を選択に追加しました。'}
})
$script:selectionTimer.Start()
