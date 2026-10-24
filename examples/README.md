# フォルダをドロップするBATサンプル

インストール版・ZIP版の`examples`フォルダで使います。1つの音楽フォルダをBATへドラッグしてください。元フォルダの直下の音声を読み、`examples/output/QitesXmlLoader-xxxxxxxx`へコピーとMusicBee向けリストを生成します。元音声は変更しません。FFmpegやPythonは不要です。複数フォルダを同時にドロップする操作は対象外です。

- `Export-Folder.bat`：確認はNG扱い。ネットワーク参照と代替参照を許可せず、参照できない曲はスキップします。
- `Export-Folder-Approve.bat`：許可できる確認を承認。NASなどの参照と、一意な同名候補の採用を許可します。存在しない曲や複数候補のどれかを勝手に選ばず、未解決の曲はスキップします。

単一フォルダローダーは、読み込んだフォルダ以外を探索しません。両BATは`Export-Folder.ps1`からJSON Linesコマンドを送ります。フォルダ名を実行コードに組み込みません。出力先やEXEの場所を指定する場合は、PowerShellからスクリプトを呼びます。

Ignoreは曲ごとの参照問題に対する方針です。入力元の読込失敗、XMLの解析失敗、出力の書込失敗まで無視するものではありません。NASフォルダ自体を入力する場合は、ネットワークアクセスを許可するApprove版を使います。

```powershell
.\Export-Folder.ps1 -Source 'C:\Music\Album' -Destination 'D:\Exports' -Policy Ignore -Program 'D:\Apps\QitesXmlLoader\QitesXmlLoader.exe'
```

終了後は画面の出力先を確認し、キーを押してBATの画面を閉じます。処理は合成フォルダで検証しています。NASの実機接続は検証していません。
