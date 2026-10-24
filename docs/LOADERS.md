# 入力ローダー

左上の選択欄で、読み込む形式を選びます。標準は「iTunes XML」です。「単一フォルダ（サンプル）」を選ぶと、指定したフォルダの直下にある音声ファイルを1つのプレイリストとして読み込みます。サブフォルダは読みません。

単一フォルダのサンプルは、ファイル名を曲名にし、名前順に並べます。アーティスト名やアルバム情報のタグ読込は実装していません。WAVとWindows標準デコーダーで読める一部形式では時間も調べます。時間が分からない曲は0として表示するため、その曲のシークやリスト総時間は制限されます。コピー・通常のハードリンク出力・対応形式の試聴は利用できます。拡張ハードリンク同期とXMLキャッシュはiTunes XML用です。

ローダーを切り替えると、表示と曲の選択をクリアします。ローダーと最後に読み込んだ入力先はGUI設定へ保存します。単一フォルダの場合は次回起動時にもそのフォルダを読みます。パイプモードの設定はセッション内だけです。

## ローダーを追加する

アプリの`loaders`フォルダに、JSON定義とPowerShellスクリプトを置き、アプリを再起動します。これらのスクリプトはアプリと同じ権限で実行する拡張コードです。信頼できるコードだけを置いてください。XMLの中に書かれた指示や実行ファイルは読み込みません。

定義例:

```json
{
  "Id": "my-source",
  "Names": {"ja": "独自XML", "en": "Custom XML"},
  "Input": "xml",
  "Script": "MySource.ps1"
}
```

`Id`は半角小文字・数字・ハイフンで一意にします。`Input`は`xml`または`folder`です。`Script`には同じフォルダ内のスクリプト名だけを指定できます。絶対パス、サブフォルダ、親フォルダへの参照は使えません。

スクリプトは`Path`と`Operation`を受け取り、次の形式のオブジェクトを**1つだけ**返します。

```powershell
param([string]$Path, [QitesXmlLoader.Operation]$Operation)
$Operation.Check()
# Parse the requested source into these dictionaries and arrays.
$library = @{
    Tracks = @{
        '1' = @{
            Name = 'Sample'
            Artist = ''
            Location = ([uri]'C:\Music\Sample.wav').AbsoluteUri
            'Total Time' = 120000 # milliseconds
        }
    }
    Playlists = @(@{
        Name = 'Sample list'
        'Playlist Persistent ID' = '1111111111111111'
        'Playlist Items' = @(@{ 'Track ID' = '1' })
    })
}
[pscustomobject]@{ Kind = 'Library'; Library = $library }
```

`Tracks`には入力元の全曲情報を入れます。どのプレイリストにも入っていない曲でも、同名ファイルの参照候補になります。`Location`はローカル音声のfile URIです。`Playlist Persistent ID`は安定した一意の16桁16進数を推奨します。親フォルダには`Folder = $true`、子には`Parent Persistent ID`を指定できます。iTunes形式では`Smart Info`または`Smart Criteria`があるリストをスマートとして表示します。

長い処理では`Operation.Report(stage, done, total, detail)`で件数・容量・段階を表示し、適切な区切りで`Operation.Check()`を呼びます。これが一時停止・キャンセルの割り込み点です。元XMLや元音声を書き換えず、ハンドルを閉じてから待機してください。元音声の追加・削除、iTunes操作、ストア接続は行わないでください。出力が必要な拡張は、無関係なファイルを復旧対象へ入れず、`Operation`の生成物管理を使ってください。

通常の拡張ローダーは`Kind = 'Library'`を返します。同梱のiTunesローダーは`Kind = 'ITunesXml'`とXMLパスを返し、既存の共有読込・キャッシュ処理へ接続します。任意形式向けの共通差分キャッシュは未実装です。
