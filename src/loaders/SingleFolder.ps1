param([string]$Path,[QitesXmlLoader.Operation]$Operation)
$ErrorActionPreference='Stop'
if(-not [IO.Directory]::Exists($Path)){throw (T '入力フォルダが見つかりません。')}
$Operation.Report((T 'フォルダ内のファイルを列挙'),0,0,$Path);$Operation.Check()
$extensions=@('.mp3','.m4a','.aac','.flac','.wav','.opus','.ogg','.wma','.aif','.aiff','.alac','.mka','.dsf','.dff')
$files=New-Object 'System.Collections.Generic.List[object]'
foreach($entry in Get-ChildItem -LiteralPath $Path -File){$Operation.Check();if($entry.Extension.ToLowerInvariant() -in $extensions){$files.Add($entry)};if($files.Count%64 -eq 0){$Operation.Report((T 'フォルダ内のファイルを列挙'),$files.Count,0,$Path)}}
$bytes=0L;foreach($file in $files){$Operation.Check();$bytes+=$file.Length}
$Operation.Report((T 'フォルダ全体容量確認'),$files.Count,$files.Count,((T '{0} 曲 / 元ファイル合計 {1:N0} bytes（重複含む）') -f $files.Count,$bytes));$Operation.Check()
$tracks=@{};$items=New-Object 'System.Collections.Generic.List[object]';$number=0
foreach($file in $files | Sort-Object Name){
 $Operation.Check();$number++;$Operation.Report((T 'フォルダから曲情報を構築'),$number,$files.Count,$file.Name)
 $duration=0L;$reader=$null
 try{
  if($file.Extension -ieq '.wav'){$reader=New-Object NAudio.Wave.WaveFileReader($file.FullName)}
  elseif($file.Extension -in @('.mp3','.m4a','.aac','.wma')){$reader=New-Object NAudio.Wave.MediaFoundationReader($file.FullName)}
  if($reader){$duration=[long]$reader.TotalTime.TotalMilliseconds}
 }catch{$duration=0L}finally{if($reader){$reader.Dispose()}}
 $tracks[[string]$number]=@{Name=$file.BaseName;Artist='';Location=([uri]$file.FullName).AbsoluteUri;'Total Time'=$duration}
 $items.Add(@{'Track ID'=[string]$number})
}
$sha=[Security.Cryptography.SHA256]::Create()
try{$id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant())))).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
$library=@{Tracks=$tracks;Playlists=@(@{Name=(New-Object IO.DirectoryInfo($Path)).Name;'Playlist Persistent ID'=$id;'Playlist Items'=$items.ToArray()})}
[pscustomobject]@{Kind='Library';Library=$library}
