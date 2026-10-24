#Requires -Version 5.1
param([string]$LibraryXml,[string]$DiagnosticsPath,[string]$CacheDirectory,[ValidateSet('ja','en')][string]$Language)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
Add-Type -AssemblyName PresentationFramework,System.Windows.Forms
$script:appRoot=$PSScriptRoot
$script:logRoot=Join-Path $env:LOCALAPPDATA 'QitesXmlLoader/Logs'
if($DiagnosticsPath){$script:logRoot=$DiagnosticsPath}
[IO.Directory]::CreateDirectory($script:logRoot) | Out-Null
$script:cacheRoot=Join-Path $env:LOCALAPPDATA 'QitesXmlLoader/Cache'
if($CacheDirectory){$script:cacheRoot=$CacheDirectory}
$script:settingsPath=Join-Path (Split-Path $script:logRoot -Parent) 'settings.json'
$script:settings=Read-AppSettings $script:settingsPath
if($Language){$script:settings.Language=$Language}
Set-AppLanguage $script:settings.Language
$script:AllowNetworkPaths=[bool]$script:settings.AllowNetworkPaths
$script:encoder=Resolve-FFmpeg $script:settings.FFmpegPath
[xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Qites xml loader" Width="1320" Height="1040" MinWidth="1100" MinHeight="850" Background="#F3F5F9" WindowStartupLocation="CenterScreen">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="14,8"/><Setter Property="Margin" Value="4"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#CCD4DF"/></Style>
  <Style TargetType="TextBox"><Setter Property="Padding" Value="8"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
 </Window.Resources>
 <Grid Margin="20">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Margin="0,0,0,8">
   <DockPanel><Button x:Name="AboutApp" DockPanel.Dock="Right" Content="このアプリについて"/><ComboBox x:Name="LanguagePicker" DockPanel.Dock="Right" Width="140" Padding="6"><ComboBoxItem Content="日本語" Tag="ja"/><ComboBoxItem Content="English" Tag="en"/></ComboBox><TextBlock Text="Qites xml loader" FontSize="27" FontWeight="Bold" Foreground="#173153"/></DockPanel>
   <TextBlock Text="iTunesのプレイリストを、いつもの曲順で持ち出す" FontSize="14" Margin="0,5,0,12"/>
   <Border Background="#FFF0CF" Padding="10"><TextBlock Text="入力元を読み込み、選択した曲やプレイリスト全体を試聴できます。"/></Border>
  </StackPanel>
  <Grid Grid.Row="1">
   <Grid.ColumnDefinitions><ColumnDefinition Width="275"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Background="White" Padding="12" CornerRadius="8">
    <DockPanel>
     <StackPanel DockPanel.Dock="Top"><ComboBox x:Name="SourceLoader" DisplayMemberPath="Name" Padding="6" Margin="4"/><Button x:Name="HardlinkMode" Content="拡張ハードリンク同期…"/><Button x:Name="LoadXml" Content="入力元を読込…"/><Button x:Name="CheckUpdate" Content="入力元の更新を確認"/><TextBlock Text="プレイリスト" FontSize="18" FontWeight="Bold"/><TextBlock Text="右クリックで全曲を選択に追加" Margin="0,6,0,14" Foreground="#667085"/></StackPanel>
     <TextBlock DockPanel.Dock="Bottom" Text="ローダーが返したプレイリスト" Foreground="#667085" Margin="0,12,0,0"/>
     <TreeView x:Name="Playlists" BorderThickness="0" HorizontalContentAlignment="Stretch">
      <TreeView.ContextMenu><ContextMenu><MenuItem x:Name="AddPlaylistSelection" Header="全体を表示して選択に追加"/></ContextMenu></TreeView.ContextMenu><TreeView.ItemTemplate><HierarchicalDataTemplate ItemsSource="{Binding Children}"><StackPanel Orientation="Horizontal"><CheckBox AutomationProperties.Name="{Binding DisplayName}" IsThreeState="True" IsChecked="{Binding SelectedState, Mode=TwoWay}" VerticalAlignment="Center"/><TextBlock Text="{Binding DisplayName}" VerticalAlignment="Center" Margin="4,3"/></StackPanel></HierarchicalDataTemplate></TreeView.ItemTemplate>
     </TreeView>
    </DockPanel>
   </Border>
   <Border Grid.Column="2" Background="White" Padding="12" CornerRadius="8">
    <DockPanel><StackPanel DockPanel.Dock="Top" Margin="0,0,0,12"><TextBlock x:Name="ListTitle" Text="曲一覧" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="ListSummary" Foreground="#667085" Margin="0,6,0,0"/></StackPanel>
     <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
      <DockPanel><Button x:Name="ClearSelection" DockPanel.Dock="Right" Content="曲の選択を解除"/><TextBlock x:Name="SelectedTrack" Text="Ctrl・Shift・ドラッグで複数曲を選択" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/></DockPanel>
      <Grid Margin="0,5,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="155"/><ColumnDefinition Width="155"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel Margin="0,0,8,0"><TextBlock Text="再生対象"/><ComboBox x:Name="PlayScope" SelectedIndex="0" Padding="5"><ComboBoxItem Content="選択した曲"/><ComboBoxItem Content="プレイリスト全体"/></ComboBox></StackPanel>
       <StackPanel Grid.Column="1" Margin="0,0,8,0"><TextBlock Text="再生順"/><ComboBox x:Name="PlayMode" SelectedIndex="0" Padding="5"><ComboBoxItem Content="通常"/><ComboBoxItem Content="ループ"/><ComboBoxItem Content="ランダム"/><ComboBoxItem Content="ランダムループ"/></ComboBox></StackPanel>
       <StackPanel Grid.Column="2"><TextBlock Text="再生デバイス"/><ComboBox x:Name="OutputDevice" DisplayMemberPath="Name" Padding="5"/></StackPanel><Button x:Name="RefreshDevices" Grid.Column="3" Content="デバイス更新" VerticalAlignment="Bottom" Padding="8,6"/>
      </Grid><TextBlock x:Name="DeviceStatus" TextTrimming="CharacterEllipsis" Foreground="#667085"/>
      <Grid x:Name="PlaybackStrip" Margin="0,4,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel Orientation="Horizontal"><Button x:Name="PlayAudio" Content="再生" Padding="8,6"/><Button x:Name="PauseAudio" Content="一時停止" Padding="8,6"/><Button x:Name="StopAudio" Content="停止" Padding="8,6"/><Button x:Name="TestSound" Content="出力テスト音" Padding="8,6"/></StackPanel>
       <Slider x:Name="MusicSeek" Grid.Column="1" Minimum="0" Maximum="1" IsEnabled="False" VerticalAlignment="Center" Margin="8,0" ToolTip="曲の再生位置" AutomationProperties.Name="曲の再生位置"/>
       <TextBlock x:Name="TrackElapsed" Grid.Column="2" Text="0:00" VerticalAlignment="Center" ToolTip="曲の再生時間"/>
       <TextBlock x:Name="TrackTotal" Grid.Column="3" Text=" / 0:00" VerticalAlignment="Center" ToolTip="曲の全体時間"/>
       <TextBlock x:Name="PlaylistClock" Grid.Column="4" Text="" Margin="14,0,0,0" VerticalAlignment="Center" ToolTip="表示中のプレイリストでの位置と総時間（XMLの曲順）"/>
      </Grid>
      <TextBlock x:Name="AudioStatus" Text="音声待機" TextWrapping="Wrap" Foreground="#245CD6"/>
     </StackPanel>
     <DataGrid x:Name="Tracks" SelectionMode="Extended" SelectionUnit="FullRow" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="False" CanUserAddRows="False" GridLinesVisibility="Horizontal" HeadersVisibility="Column" BorderThickness="0" RowHeight="35" Background="White">
      <DataGrid.ContextMenu><ContextMenu><MenuItem x:Name="PreviewMenu" Header="選択した曲を再生"/></ContextMenu></DataGrid.ContextMenu>
      <DataGrid.Columns><DataGridTextColumn Header="#" Binding="{Binding Order}" Width="40"/><DataGridTextColumn Header="曲名" Binding="{Binding Title}" Width="*"/><DataGridTextColumn Header="アーティスト" Binding="{Binding Artist}" Width="140"/><DataGridTextColumn Header="プレイリスト" Binding="{Binding PlaylistName}" Width="140"/><DataGridTextColumn Header="時間" Binding="{Binding Duration}" Width="65"/><DataGridTextColumn Header="形式" Binding="{Binding Format}" Width="65"/></DataGrid.Columns>
     </DataGrid>
    </DockPanel>
   </Border>
  </Grid>
  <Border Grid.Row="2" Background="White" CornerRadius="8" Padding="12" Margin="0,10,0,0">
   <StackPanel>
    <DockPanel><Button x:Name="SaveFFmpeg" DockPanel.Dock="Right" Content="パスを保存"/><Button x:Name="BrowseFFmpeg" DockPanel.Dock="Right" Content="参照…"/><TextBlock Text="FFmpegの場所" Width="100" VerticalAlignment="Center"/><TextBox x:Name="FFmpegPath" ToolTip="ffmpeg.exe、binフォルダ、または空欄でPATHを検索"/></DockPanel><TextBlock x:Name="EncoderStatus" TextWrapping="Wrap" Foreground="#667085" Margin="100,2,0,5"/>
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="85"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="出力先" VerticalAlignment="Center"/><TextBox x:Name="Destination" Grid.Column="1" ToolTip="プレイリストごとのフォルダをこの中に作成します"/><Button x:Name="Browse" Grid.Column="2" Content="参照…"/></Grid>
    <Grid Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="85"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="出力方法" VerticalAlignment="Center"/><DockPanel Grid.Column="1"><ComboBox x:Name="ExportScope" DockPanel.Dock="Right" Width="220" SelectedIndex="0" Padding="6"><ComboBoxItem Content="チェックしたプレイリスト"/><ComboBoxItem Content="選択した曲"/></ComboBox><ComboBox x:Name="Mode" Padding="6"/></DockPanel></Grid>
    <DockPanel Margin="0,8,0,0"><TextBlock Text="読み込み先" Width="85" VerticalAlignment="Center"/><Button x:Name="ExportSelection" DockPanel.Dock="Right" Content="選択中の曲を書き出す…"/><ComboBox x:Name="ExportTarget" SelectedIndex="0" Padding="6"><ComboBoxItem Content="標準（M3U8）" Tag="Generic"/><ComboBoxItem Content="MusicBee" Tag="MusicBee"/><ComboBoxItem Content="foobar2000" Tag="Foobar2000"/><ComboBoxItem Content="AIMP" Tag="Aimp"/><ComboBoxItem Content="reTONE（Musicフォルダ）" Tag="Retone"/></ComboBox></DockPanel>
    <CheckBox x:Name="AsciiNames" Content="互換性のためファイル名を英数字にする" Margin="85,5,0,0"/>
    <TextBlock x:Name="TargetHint" Margin="85,4,0,0" Foreground="#667085" TextWrapping="Wrap"/>
    <TextBlock x:Name="ModeHint" TextWrapping="Wrap" Foreground="#667085" Margin="85,8,0,8"/>
    <Expander Header="曲が見つからない場合"><StackPanel Margin="85,5,0,6"><WrapPanel><TextBlock Text="見つからない曲" VerticalAlignment="Center"/><ComboBox x:Name="MissingPolicy" SelectedIndex="0" Padding="5" Margin="8,0"><ComboBoxItem Content="処理を止める" Tag="Stop"/><ComboBoxItem Content="無視して続ける" Tag="Skip"/></ComboBox><Button x:Name="ApplyFileOptions" Content="保存して存在を再確認" Padding="8,5"/></WrapPanel><CheckBox x:Name="ResolveLibraryNames" Content="ライブラリ内の同名ファイルを参照する" Margin="0,5"/><CheckBox x:Name="AllowNetworkPaths" Content="ネットワーク上のファイル参照を許可（NASなど）" Margin="0,3"/><TextBlock Text="XMLの全曲情報に登録されたパスだけを確認します。実在する同名ファイルが1つなら参照し、2つ以上なら未解決にします。元XMLは変更しません。" TextWrapping="Wrap" Foreground="#667085"/></StackPanel></Expander>
    <Expander x:Name="Advanced" Header="エンコーダーの詳細設定"><StackPanel Margin="85,8,0,4"><TextBlock Text="FFmpegの出力オプション（入力・出力ファイル名はアプリが指定）"/><TextBox x:Name="Options" Text="-codec:a libmp3lame -q:a 2" Margin="0,6,0,0" FontFamily="Consolas"/><WrapPanel><TextBlock Text="カスタム拡張子" VerticalAlignment="Center"/><TextBox x:Name="CustomExtension" Text="mka" Width="75" Margin="6"/><TextBlock Text="コンテナー" VerticalAlignment="Center"/><TextBox x:Name="CustomMuxer" Text="matroska" Width="115" Margin="6"/></WrapPanel></StackPanel></Expander>
    <TextBlock Text="各フォルダに曲と相対パスのM3U8を保存し、プレイリストの曲順を維持します。" Margin="0,10,0,0" Foreground="#667085"/>
   </StackPanel>
  </Border>
  <StackPanel Grid.Row="3" Margin="0,12,0,0">
   <TextBlock x:Name="Status" Text="準備完了" FontWeight="Bold" TextTrimming="CharacterEllipsis"/>
   <TextBlock x:Name="ProgressDetail" Text="処理進捗・全体件数・容量をここに表示します" TextTrimming="CharacterEllipsis" Margin="0,4,0,4"/>
   <TextBlock Text="容量確認 → XML読込・差分照合 → ファイル確認 → 変換・コピー・リンク同期 → 完了" Foreground="#667085" FontSize="11" Margin="0,0,0,4"/><ProgressBar x:Name="Progress" Minimum="0" Maximum="100" Height="12"/>
   <WrapPanel Margin="0,5,0,0"><Button x:Name="PauseWork" Content="処理を一時停止" IsEnabled="False"/><Button x:Name="CancelWork" Content="即時中止" IsEnabled="False"/><Button x:Name="RollbackWork" Content="復旧して中止" IsEnabled="False"/><Button x:Name="UndoPartial" Content="途中出力を復旧" IsEnabled="False"/><Button x:Name="Review" Content="書き出し内容を確認" Background="#245CD6" Foreground="White" FontWeight="Bold"/></WrapPanel>
  </StackPanel>
 </Grid>
</Window>
'@
Initialize-LocalizedMarkup $markup
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $markup))
$ui=@{}
'AllowNetworkPaths','SourceLoader','MissingPolicy','ResolveLibraryNames','ApplyFileOptions','PlaybackStrip','MusicSeek','TrackElapsed','TrackTotal','PlaylistClock','ExportTarget','ExportSelection','AsciiNames','TargetHint','AboutApp','LanguagePicker','FFmpegPath','BrowseFFmpeg','SaveFFmpeg','EncoderStatus','ExportScope','CustomExtension','CustomMuxer','AddPlaylistSelection','ClearSelection','OutputDevice','RefreshDevices','DeviceStatus','HardlinkMode','LoadXml','CheckUpdate','Playlists','Tracks','ListTitle','ListSummary','SelectedTrack','PlayScope','PlayMode','PlayAudio','PauseAudio','StopAudio','TestSound','PreviewMenu','AudioStatus','Destination','Browse','Mode','ModeHint','Advanced','Options','Status','ProgressDetail','Progress','PauseWork','CancelWork','RollbackWork','UndoPartial','Review' | ForEach-Object {$ui[$_]=$window.FindName($_)}
$script:applyingLanguage=$true
$script:formats=@(Get-OutputFormats)
foreach($format in $script:formats){$item=New-Object Windows.Controls.ComboBoxItem;$item.Content=T $format.Label;$item.Tag=$format.Id;[void]$ui.Mode.Items.Add($item)}
$ui.Mode.SelectedIndex=$(if($script:encoder){2}else{0})
$ui.LanguagePicker.SelectedIndex=$(if($script:settings.Language -eq 'ja'){0}else{1})
$ui.FFmpegPath.Text=$script:settings.FFmpegPath
$script:sourceLoaders=@(Get-SourceLoaders);$ui.SourceLoader.ItemsSource=$script:sourceLoaders
$sourceId=if($LibraryXml){'itunes'}else{$script:settings.SourceLoader}
$ui.SourceLoader.SelectedItem=$script:sourceLoaders | Where-Object Id -eq $sourceId | Select-Object -First 1
if(-not $ui.SourceLoader.SelectedItem){$ui.SourceLoader.SelectedItem=$script:sourceLoaders | Where-Object Id -eq 'itunes' | Select-Object -First 1}
$ui.MissingPolicy.SelectedIndex=$(if($script:settings.MissingPolicy -eq 'Skip'){1}else{0});$ui.ResolveLibraryNames.IsChecked=[bool]$script:settings.ResolveLibraryNames;$ui.AllowNetworkPaths.IsChecked=[bool]$script:settings.AllowNetworkPaths
Apply-AppLanguage
$icon=Join-Path $PSScriptRoot 'assets/QitesXmlLoader.ico'
if(-not [IO.File]::Exists($icon)){$icon=Join-Path (Split-Path $PSScriptRoot -Parent) 'assets/QitesXmlLoader.ico'}
$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$icon)
. (Join-Path $PSScriptRoot 'Selection.ps1')
. (Join-Path $PSScriptRoot 'Playback.ps1')
. (Join-Path $PSScriptRoot 'About.ps1')
$script:applyingLanguage=$false
$script:rootNodes=@();$script:leafNodesInOrder=@();$script:nodesById=@{};$script:data=@();$script:busy=$false;$script:job=$null;$script:lastPartial=$null;$script:xmlPath=$null;$script:LibraryPaths=@();$script:pendingExport=$null;$script:pendingSync=$null;$script:confirmationMemory=@{}
function Write-OperationEvent($name,$detail){Add-Content -LiteralPath (Join-Path $script:logRoot 'operations.jsonl') -Value (([pscustomobject]@{Time=(Get-Date).ToString('o');Event=$name;Detail=$detail}) | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8}
function Set-Busy($value){
 $script:busy=$value
 foreach($name in @('LoadXml','CheckUpdate','HardlinkMode','Review','Browse','Destination','Mode','Options','Playlists','ExportScope','CustomExtension','CustomMuxer','FFmpegPath','SaveFFmpeg','BrowseFFmpeg','ClearSelection','LanguagePicker','ExportSelection','ExportTarget','AsciiNames','AllowNetworkPaths','SourceLoader','MissingPolicy','ResolveLibraryNames','ApplyFileOptions')){$ui[$name].IsEnabled=-not $value}
 foreach($name in @('PauseWork','CancelWork','RollbackWork')){$ui[$name].IsEnabled=$value}
 $ui.UndoPartial.IsEnabled=(-not $value -and $null -ne $script:lastPartial)
}
function Start-Operation([string]$kind,$arguments,$existingOperation=$null){
 if($script:busy){return}
 if(-not $arguments.ContainsKey('Trial')){if($script:confirmationMemory.Count -ge 128){$script:confirmationMemory.Clear()};$arguments.Trial=[guid]::NewGuid().ToString('N')}
 $operation=$existingOperation;if($null -eq $operation){$operation=New-Object QitesXmlLoader.Operation}
 $operation.PauseRequested=$false;$operation.Cancel=0
 $result=[hashtable]::Synchronized(@{Finished=$false;State='Running';Message='';Error='';Data=$null;Path='';XmlPath='';Summary=''})
 $ps=[PowerShell]::Create();$ps.Runspace=[RunspaceFactory]::CreateRunspace();$ps.Runspace.Open()
 $arguments.CacheRoot=$script:cacheRoot
 $arguments.AllowNetworkPaths=[bool]$ui.AllowNetworkPaths.IsChecked
 $arguments.SourceLoader=[string]$ui.SourceLoader.SelectedItem.Id
 $arguments.LibraryPaths=$script:LibraryPaths;$arguments.ResolveLibraryNames=[bool]$ui.ResolveLibraryNames.IsChecked;$arguments.MissingPolicy=[string]$ui.MissingPolicy.SelectedItem.Tag
 [void]$ps.AddCommand((Join-Path $script:appRoot 'Worker.ps1')).AddParameter('AppRoot',$script:appRoot).AddParameter('Kind',$kind).AddParameter('Arguments',$arguments).AddParameter('Operation',$operation).AddParameter('Result',$result)
 $script:job=@{PS=$ps;Handle=$null;Operation=$operation;Result=$result;Kind=$kind;LastStage='';Arguments=$arguments}
 Set-Busy $true;$ui.PauseWork.Content=(T '処理を一時停止');$ui.Progress.IsIndeterminate=$true;$ui.Status.Text=(T '開始: ')+$kind
 $script:job.Handle=$ps.BeginInvoke();Write-OperationEvent 'Started' @{Kind=$kind;Journal=$operation.JournalPath}
}
function Set-Library($lists){
 $selectedIds=@();if(Get-Variable nodesById -Scope Script -ErrorAction SilentlyContinue){$selectedIds=@($script:nodesById.Values | Where-Object Selected | ForEach-Object Id)}
 $map=@{};$orderedNodes=New-Object 'System.Collections.Generic.List[object]';$roots=New-Object 'System.Collections.Generic.List[object]';$leaves=New-Object 'System.Collections.Generic.List[object]';$counter=0
 foreach($list in $lists){
  $counter++;$node=New-Object QitesXmlLoader.PlaylistNode;$node.Id=$list.Id;if(-not $node.Id){$node.Id='row-'+$counter}
  if($map.ContainsKey($node.Id)){throw (T 'プレイリストIDが重複しています。')}
  $node.Name=$list.Name;$node.IsFolder=$list.IsFolder;$node.IsSmart=$list.IsSmart;$node.Payload=$list;$node.LeafTracks=[object[]]$list.Tracks
  $map[$node.Id]=$node;$orderedNodes.Add($node);if(-not $node.IsFolder){$leaves.Add($node)}
 }
 foreach($node in $orderedNodes){
  $list=$node.Payload;$parentId=$list.ParentId;$seen=@($node.Id)
  while($parentId -and $map.ContainsKey($parentId)){
   if($parentId -in $seen){throw (T 'プレイリスト階層が循環しています。')};$seen+=$parentId;$parentId=$map[$parentId].Payload.ParentId
  }
  if($list.ParentId -and $map.ContainsKey($list.ParentId) -and $map[$list.ParentId].IsFolder){$node.Parent=$map[$list.ParentId];$node.Parent.Children.Add($node)}else{$roots.Add($node)}
 }
 foreach($node in $leaves){if($node.Id -in $selectedIds){$node.Selected=$true}}
 $newTracks=@{};foreach($list in $lists){foreach($track in $list.Tracks){$newTracks[(Get-TrackSelectionKey $track)]=$track}}
 $retained=[ordered]@{};foreach($key in @($script:selectedTracks.Keys)){if($newTracks.ContainsKey($key)){$retained[$key]=$newTracks[$key]}};$script:selectedTracks=$retained
 $script:data=@($lists);$script:nodesById=$map;$script:leafNodesInOrder=$leaves.ToArray();$script:rootNodes=$roots.ToArray()
 $ui.Playlists.ItemsSource=$script:rootNodes
 if($roots.Count){Set-VisiblePlaylist $roots[0]}else{$ui.Tracks.ItemsSource=$null;$script:visiblePlaylist=$null;$ui.ListTitle.Text=T '曲一覧';$ui.ListSummary.Text='';Update-PlaylistTimeline;Update-PlaybackTimeline}
}
$ui.SourceLoader.Add_SelectionChanged({
 if($script:applyingLanguage){return}
 Stop-Playback;$script:xmlPath=$null;Set-Library -lists @()
 $script:LibraryPaths=@();$script:settings.SourceLoader=[string]$ui.SourceLoader.SelectedItem.Id;$script:settings.SourcePath='';Save-AppSettings $script:settingsPath $script:settings
 $ui.Status.Text=T '入力元を選択してください。'
})
$ui.LoadXml.Add_Click({
 $requestedPath=$null
 if($ui.SourceLoader.SelectedItem.Input -eq 'folder'){$dialog=New-Object System.Windows.Forms.FolderBrowserDialog;try{if($dialog.ShowDialog() -eq 'OK'){$requestedPath=$dialog.SelectedPath}}finally{$dialog.Dispose()}}
 else{$dialog=New-Object Microsoft.Win32.OpenFileDialog;$dialog.Filter='XML (*.xml)|*.xml';if($dialog.ShowDialog() -eq $true){$requestedPath=$dialog.FileName}}
 if($requestedPath){Start-Operation 'Load' @{Path=$requestedPath}}
})
$ui.CheckUpdate.Add_Click({if($script:xmlPath){Start-Operation 'Load' @{Path=$script:xmlPath}}else{$ui.Status.Text=T '入力元を先に選択してください。'}})
$ui.Destination.Text=Join-Path ([Environment]::GetFolderPath('MyMusic')) 'Qites xml loader'
$ui.Browse.Add_Click({$dialog=New-Object System.Windows.Forms.FolderBrowserDialog;try{if($dialog.ShowDialog() -eq 'OK'){$ui.Destination.Text=$dialog.SelectedPath}}finally{$dialog.Dispose()}})
$ui.HardlinkMode.Add_Click({
 if($ui.SourceLoader.SelectedItem.Id -ne 'itunes'){$ui.Status.Text=T '拡張同期はiTunes XML用です。フォルダは通常のハードリンク出力を使ってください。';return}
 if(-not $script:xmlPath){$ui.Status.Text=(T 'ライブラリXMLを先に選択してください。');return}
 if([Windows.MessageBox]::Show((T '元音声と同じボリュームへハードリンクを生成・再同期します。出力音声は編集しないでください。'),(T '拡張ハードリンク同期'),'OKCancel') -eq 'OK'){$script:pendingSync=@{Path=$script:xmlPath;Destination=$ui.Destination.Text};Start-Operation 'CheckSync' $script:pendingSync}
})
function Update-EncoderStatus {
 $script:encoder=Resolve-FFmpeg $script:settings.FFmpegPath
 $ui.EncoderStatus.Text=$(if($script:encoder){T 'FFmpeg: {0}' @($script:encoder)}else{T 'FFmpeg未検出。コピー・ハードリンク・Windows対応形式の試聴は利用できます。'})
}
$ui.BrowseFFmpeg.Add_Click({$dialog=New-Object Microsoft.Win32.OpenFileDialog;$dialog.Filter='FFmpeg (ffmpeg.exe)|ffmpeg.exe';if($dialog.ShowDialog() -eq $true){$ui.FFmpegPath.Text=$dialog.FileName}})
$ui.SaveFFmpeg.Add_Click({try{$script:settings.FFmpegPath=$ui.FFmpegPath.Text.Trim();Save-AppSettings $script:settingsPath $script:settings;Update-EncoderStatus}catch{$ui.Status.Text=$_.Exception.Message}})
function Update-ModeHint {
 $format=$script:formats[$ui.Mode.SelectedIndex]
 $ui.ModeHint.Text=$(if($format.Id -eq 'Copy'){T 'FFmpeg不要。元ファイルを変更せずコピーします。'}elseif($format.Id -eq 'Hardlink'){T 'FFmpeg不要。同じボリューム内で、元音声と内容を共有します。'}else{T 'FFmpegで変換します。音質・コーデックは詳細設定で調整できます。'})
}
$updateMode={
 if($script:applyingLanguage){return}
 $format=$script:formats[$ui.Mode.SelectedIndex]
 $ui.Advanced.IsEnabled=$format.Id -notin @('Copy','Hardlink')
 $ui.CustomExtension.IsEnabled=$format.Id -eq 'Custom';$ui.CustomMuxer.IsEnabled=$format.Id -eq 'Custom'
 $ui.Options.Text=$format.Options
 Update-ModeHint
}
$ui.Mode.Add_SelectionChanged($updateMode);& $updateMode;Update-EncoderStatus
$ui.LanguagePicker.Add_SelectionChanged({
 if($script:applyingLanguage){return}
 $script:applyingLanguage=$true
 try{
  $language=[string]$ui.LanguagePicker.SelectedItem.Tag;Set-AppLanguage $language;$script:settings.Language=$language;Save-AppSettings $script:settingsPath $script:settings
  Apply-AppLanguage
  $activeSource=[string]$ui.SourceLoader.SelectedItem.Id;$script:sourceLoaders=@(Get-SourceLoaders);$ui.SourceLoader.ItemsSource=$script:sourceLoaders;$ui.SourceLoader.SelectedItem=$script:sourceLoaders | Where-Object Id -eq $activeSource | Select-Object -First 1
  for($i=0;$i -lt $script:formats.Count;$i++){$ui.Mode.Items[$i].Content=T $script:formats[$i].Label}
  foreach($node in $script:rootNodes){$node.RefreshNames()}
  $ui.Playlists.Items.Refresh();Refresh-OutputDevices;Update-SelectionSummary;Update-EncoderStatus;Update-ModeHint;Update-TargetHint;Update-PlaybackTimeline
  if(-not $script:playing -and $null -eq $script:testPlayer){$ui.AudioStatus.Text=T '音声待機'}
  $ui.ProgressDetail.Text=''
  if($script:visiblePlaylist){$ui.ListSummary.Text=T '{0}曲 · XMLに保存された曲順' @($script:visiblePlaylist.Tracks.Count)}
  $ui.Status.Text=T '言語とフォント設定を適用しました。'
 }finally{$script:applyingLanguage=$false}
})
function Request-Export([bool]$SelectionOnly=$false){
 [void]$window.Focus()
 if($SelectionOnly -or $ui.ExportScope.SelectedIndex -eq 1){$selected=@([pscustomobject]@{Name=(T '選択した曲');Tracks=@($script:selectedTracks.Values)})}
 else{$selected=@($script:leafNodesInOrder | Where-Object Selected | ForEach-Object Payload)}
 if(-not $selected.Count -or @($selected | ForEach-Object Tracks).Count -eq 0){$ui.Status.Text=T '曲またはプレイリストを選択してください。';return}
 $format=$script:formats[$ui.Mode.SelectedIndex]
 if($format.Id -notin @('Copy','Hardlink') -and -not $script:encoder){$ui.Status.Text=T '変換にはFFmpegが必要です。別途インストールしてパスを指定してください。';return}
 $message=T '対象: {0}\n出力先: {1}\n出力方法: {2}' @((($selected | ForEach-Object Name) -join ', ');$ui.Destination.Text;$ui.Mode.SelectedItem.Content)
 $message+='\n'+(T '読み込み先')+': '+$ui.ExportTarget.SelectedItem.Content
 if($ui.AsciiNames.IsChecked){$message+='\n'+(T '互換性のためファイル名を英数字にする')}
 $message=$message.Replace('\n',"`n")
 if([Windows.MessageBox]::Show($message,(T '書き出し確認'),'OKCancel') -eq 'OK'){$script:pendingExport=@{Lists=$selected;Destination=$ui.Destination.Text;Mode=$format.Id;Options=$ui.Options.Text;Encoder=$script:encoder;Hierarchy=$script:data;Extension=$ui.CustomExtension.Text;Muxer=$ui.CustomMuxer.Text;Target=[string]$ui.ExportTarget.SelectedItem.Tag;AsciiNames=[bool]$ui.AsciiNames.IsChecked};Start-Operation 'CheckExport' $script:pendingExport}
}
$ui.Review.Add_Click({Request-Export})
$ui.ExportSelection.Add_Click({Request-Export $true})
function Update-TargetHint {
 $ui.TargetHint.Text=$(if($ui.ExportTarget.SelectedItem.Tag -eq 'Generic'){T '各フォルダに曲と相対パスのM3U8を保存し、プレイリストの曲順を維持します。'}elseif($ui.ExportTarget.SelectedItem.Tag -eq 'Retone'){T 'reTONEはMusicフォルダから曲を取り込みます。外部リストの読み込みは非対応です。曲順は連番ファイル名とM3U8に保存します。'}else{T '音声ファイルと相対パスのM3U8・M3Uを出力します。アプリへ直接送信しません。'})
}
$ui.ExportTarget.Add_SelectionChanged({Update-TargetHint});Update-TargetHint
function Save-FileOptions {
 $script:settings.MissingPolicy=[string]$ui.MissingPolicy.SelectedItem.Tag;$script:settings.ResolveLibraryNames=[bool]$ui.ResolveLibraryNames.IsChecked;$script:settings.AllowNetworkPaths=[bool]$ui.AllowNetworkPaths.IsChecked;$script:AllowNetworkPaths=[bool]$ui.AllowNetworkPaths.IsChecked
 Save-AppSettings $script:settingsPath $script:settings
}
$ui.MissingPolicy.Add_SelectionChanged({if(-not $script:applyingLanguage){Save-FileOptions}})
$ui.ResolveLibraryNames.Add_Click({Save-FileOptions})
$ui.AllowNetworkPaths.Add_Click({Save-FileOptions;Update-EncoderStatus})
$ui.ApplyFileOptions.Add_Click({Save-FileOptions;if($script:data.Count){Stop-Playback;Start-Operation 'ValidateCache' @{Lists=$script:data}}})
function Confirm-FileCheck($report,[bool]$ForOutput=$false,[string]$Trial=''){
 if($Trial -and $script:confirmationMemory.ContainsKey($Trial)){return [bool]$script:confirmationMemory[$Trial]}
 if($null -eq $report -or ($report.Unresolved+$report.Resolved) -eq 0){return $true}
 $message=(Get-FileCheckMessage $report).Replace('\n',"`n")
 $details=@($report.Issues | Select-Object -First 6 | ForEach-Object { $_.Status+': '+$_.Title+' / '+$_.OriginalPath })
 if($details.Count){$message+="`n`n"+($details -join "`n")}
 if($ForOutput){
  if($report.Unresolved -gt 0 -and $ui.MissingPolicy.SelectedItem.Tag -eq 'Stop'){$message+="`n`n"+(T '処理を止める設定のため、出力は作成しません。');[void][Windows.MessageBox]::Show($window,$message,(T 'ファイル存在確認'),'OK','Warning');if($Trial){$script:confirmationMemory[$Trial]=$false};return $false}
  $message+="`n`n"+(T '参照できない曲を除き、この内容で出力しますか？')
  $default=[Windows.MessageBoxResult]::No;if($script:settings.LastFileDecision -eq 'Yes'){$default=[Windows.MessageBoxResult]::Yes}
  $choice=[Windows.MessageBox]::Show($window,$message,(T 'ファイル存在確認'),'YesNo','Warning',$default) -eq 'Yes'
  if($Trial){$script:confirmationMemory[$Trial]=$choice};$script:settings.LastFileDecision=$(if($choice){'Yes'}else{'No'});Save-AppSettings $script:settingsPath $script:settings;return $choice
 }
 [void][Windows.MessageBox]::Show($window,$message,(T 'ファイル存在確認'),'OK','Warning');if($Trial){$script:confirmationMemory[$Trial]=$true};return $true
}
$ui.PauseWork.Add_Click({
 if($script:selectionJob){$operation=$script:selectionJob.Operation;$operation.PauseRequested=-not $operation.PauseRequested;$ui.PauseWork.Content=$(if($operation.PauseRequested){T '処理を再開'}else{T '処理を一時停止'});return}
 if($script:job){$operation=$script:job.Operation;$operation.PauseRequested=-not $operation.PauseRequested;$ui.PauseWork.Content=$(if($operation.PauseRequested){(T '処理を再開')}else{(T '処理を一時停止')});Write-OperationEvent 'PauseRequested' $operation.PauseRequested}
})
$ui.CancelWork.Add_Click({if($script:selectionJob){$script:selectionJob.Operation.Cancel=1;return};if($script:job){$script:job.Operation.Cancel=1;$script:job.Operation.PauseRequested=$false;$ui.Status.Text=(T '即時中止しています…')}})
$ui.RollbackWork.Add_Click({if($script:selectionJob){$script:selectionJob.Operation.Cancel=2;return};if($script:job){$script:job.Operation.Cancel=2;$script:job.Operation.PauseRequested=$false;$ui.Status.Text=(T '停止して、今回の新規生成物を復旧しています…')}})
$ui.UndoPartial.Add_Click({if($script:lastPartial){Start-Operation 'Rollback' @{} $script:lastPartial}})
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(100)
$timer.Add_Tick({
 if(-not $script:job){return}
 try{
  $job=$script:job;$snapshot=$job.Operation.Snapshot()
  $stage=$snapshot[0];if($job.Operation.Paused){$stage=(T '一時停止中 · ')+$stage}
  $ui.Status.Text=$stage
  $total=[long]$snapshot[2];$done=[long]$snapshot[1]
  $ui.Progress.IsIndeterminate=$total -le 0
  if($total -gt 0){$ui.Progress.Value=[math]::Min(100,100.0*$done/$total)}
  $ui.ProgressDetail.Text=$(if($total -gt 0){"$done / $total · "}else{''})+$snapshot[3]
  if($stage -ne $job.LastStage){Write-OperationEvent 'Stage' @{Stage=$stage;Done=$done;Total=$total;Detail=$snapshot[3]};$job.LastStage=$stage}
  if($job.Handle.IsCompleted){
   try{[void]$job.PS.EndInvoke($job.Handle)}catch{$job.Result.State='Failed';$job.Result.Message=$_.Exception.Message}
   if($job.Result.State -eq 'Running'){$job.Result.State='Failed';$job.Result.Message=($job.PS.Streams.Error | Out-String)}
   $job.PS.Runspace.Close();$job.PS.Dispose();$script:job=$null
   $ui.Progress.IsIndeterminate=$false;Set-Busy $false;$ui.PauseWork.Content=(T '処理を一時停止')
   if($job.Operation.Cancel -eq 2 -and $job.Result.State -eq 'Complete' -and $job.Kind -ne 'Rollback'){
    Write-OperationEvent 'LateRollbackRequested' $job.Kind
    Start-Operation 'Rollback' @{} $job.Operation
    return
   }
   if($job.Operation.Cancel -eq 1 -and $job.Result.State -eq 'Complete' -and $job.Kind -ne 'Rollback'){
    $job.Result.State='Cancelled';$job.Result.Message=(T '停止要求の直前に処理が完了しました。生成物を保持しています。必要なら途中出力を復旧できます。')
   }
   Write-OperationEvent 'Finished' @{Kind=$job.Kind;State=$job.Result.State;Message=$job.Result.Message;Error=$job.Result.Error;Summary=$job.Result.Summary;Output=$job.Operation.Output;Journal=$job.Operation.JournalPath}
   if($job.Result.State -eq 'Complete'){
    $finalProgress=$job.Operation.Snapshot();$ui.Progress.Value=100
    $ui.ProgressDetail.Text=$(if([long]$finalProgress[2] -gt 0){$finalProgress[1]+' / '+$finalProgress[2]+' · '}else{''})+$finalProgress[3]
    if($job.Kind -in @('Load','Boot')){$script:LibraryPaths=@($job.Result.LibraryPaths);Set-Library $job.Result.Data;$script:xmlPath=$job.Result.XmlPath;$script:settings.SourceLoader=[string]$ui.SourceLoader.SelectedItem.Id;$script:settings.SourcePath=$script:xmlPath;Save-AppSettings $script:settingsPath $script:settings}
    $ui.Status.Text=(T '完了: ')+$job.Result.Summary+$job.Result.Path+$job.Result.Message
    if($job.Result.FileCheck){$job.Result.FileCheck | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:logRoot 'last-file-check.json') -Encoding UTF8}
    if($job.Kind -eq 'CheckExport'){if(Confirm-FileCheck $job.Result.FileCheck $true $job.Arguments.Trial){Start-Operation 'Export' $script:pendingExport};return}
    if($job.Kind -eq 'CheckSync'){if(Confirm-FileCheck $job.Result.FileCheck $true $job.Arguments.Trial){Start-Operation 'Sync' $script:pendingSync};return}
    if($job.Kind -in @('Load','ValidateCache')){[void](Confirm-FileCheck $job.Result.FileCheck $false $job.Arguments.Trial);$ui.Tracks.Items.Refresh()}
    if($job.Kind -eq 'Rollback'){$script:lastPartial=$null;$ui.UndoPartial.IsEnabled=$false}
    if($job.Kind -eq 'Boot'){
     if((Test-AllowedSourceExists $script:xmlPath 'file')){Start-Operation 'Load' @{Path=$script:xmlPath}}
     else{$ui.Status.Text=(T 'キャッシュ表示中 · 元XMLが見つかりません。更新確認は保留しています。');Start-Operation 'ValidateCache' @{Lists=$script:data}}
    }
   }else{
    if($job.Result.FileCheck){[void](Confirm-FileCheck $job.Result.FileCheck $false $job.Arguments.Trial)}
    $ui.Status.Text=$job.Result.Message
    $script:lastPartial=$job.Operation;$ui.UndoPartial.IsEnabled=$true
   }
  }
 }catch{$ui.Status.Text=(T '進捗表示エラー: ')+$_.Exception.Message;Write-OperationEvent 'UIError' $_.Exception.ToString()}
})
$timer.Start()
$window.Add_ContentRendered({
 try{Play-TestSound 'StartupSound'}catch{Write-PlaybackEvent 'StartupSoundError' $_.Exception.Message}
 if($LibraryXml){$script:xmlPath=$LibraryXml;Start-Operation 'Load' @{Path=$LibraryXml}}
 elseif($ui.SourceLoader.SelectedItem.Id -ne 'itunes'){if((Test-AllowedSourceExists $script:settings.SourcePath 'folder')){Start-Operation 'Load' @{Path=$script:settings.SourcePath}}}
 else{
  $latest=Get-ChildItem -LiteralPath $script:cacheRoot -Filter '*.cache' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if($latest){Start-Operation 'Boot' @{Path=$latest.FullName}}
 }
 Write-OperationEvent 'WindowReady' @{AppRoot=$script:appRoot;Version='0.9'}
})
$window.Add_Closing({param($sender,$eventArgs)
 if($script:busy){$eventArgs.Cancel=$true;$ui.Status.Text=(T '処理を中止または復旧してから閉じてください。');return}
 $timer.Stop();$script:playbackTimer.Stop();$script:selectionTimer.Stop();Stop-Playback
})
$window.ShowDialog() | Out-Null
