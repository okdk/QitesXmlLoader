$ui.AboutApp.Add_Click({
 $about=New-Object Windows.Window
 $about.Title=T 'このアプリについて'
 $about.Owner=$window;$about.WindowStartupLocation='CenterOwner';$about.Width=760;$about.Height=620
 $about.FontFamily=$window.FontFamily
 $panel=New-Object Windows.Controls.DockPanel;$panel.Margin='16'
 $close=New-Object Windows.Controls.Button;$close.Content=T '閉じる';$close.Padding='16,6';$close.Margin='0,12,0,0';$close.HorizontalAlignment='Right'
 [Windows.Controls.DockPanel]::SetDock($close,'Bottom');[void]$panel.Children.Add($close)
 $text=New-Object Windows.Controls.TextBox;$text.IsReadOnly=$true;$text.TextWrapping='Wrap';$text.VerticalScrollBarVisibility='Auto';$text.Padding='10';$text.BorderThickness='0'
 $content='Qites xml loader 0.9'+"`r`n`r`n"+(T 'iTunesのライブラリXMLを読み込む、Windows向けのアプリです。曲をほかのアプリへ移したいときや、iTunesの起動を待たずに試聴したいときに使えます。')+"`r`n`r`n"+(T '独立した非公式アプリです。iTunesおよびAppleはApple Inc.の商標です。AppleまたはOpenAIの公式製品ではありません。')+"`r`n`r`n"
 foreach($name in @('NOTICE.md','LICENSE','THIRD-PARTY.md','lib/NAudio-LICENSE.txt')){
  $path=Join-Path $script:appRoot $name
  if([IO.File]::Exists($path)){$content+=$name+"`r`n"+[IO.File]::ReadAllText($path)+"`r`n`r`n"}
 }
 $text.Text=$content;[void]$panel.Children.Add($text);$about.Content=$panel
 $close.Add_Click({$about.Close()}.GetNewClosure())
 [void]$about.ShowDialog()
})
