# GitHubへ公開する手順

## 先に確認すること

1. `LICENSE` はMITです。公開する権利を持つソース・素材であることと、著作権者名を確認してください。現在の名義は `okdk` です。別ライセンスにしたい場合は、公開する前に変更してください。NAudioの元ライセンスは変更しません。
2. `NOTICE.md` の商標表記と非公式アプリの説明を保ちます。Appleロゴ・iTunesアイコン・Apple製バイナリ・実楽曲・アルバムアートは掲載しません。© Appleをアプリ自身の著作権表示に使いません。
3. FFmpeg本体をZIPやインストーラーへ足さないでください。将来同梱するなら、採用ビルドごとのライセンス・対応ソースなどの配布条件を改めて確認します。
4. 実ライブラリXML、曲名・パス入りログ、キャッシュ、設定、APIキー、個人ファイルを入れません。スクリーンショットを公開する場合も合成データを使います。
5. 最終ビルドとテストを実行し、`dist` のチェックサムを記録します。未署名EXEであることと、検証範囲・既知の制限をリリースノートに書きます。コード署名は信頼性を高める選択肢です。

## 公開用ソースを作る

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Prepare-Publication.ps1
```

このスクリプトは許可したソース・文書・素材だけを新しい公開用フォルダとZIPへコピーし、実データ・ログ・依存DLL・FFmpeg・過去の配布物を入れません。出力先を表示するので、中身を一度確認してください。

**このアプリの外側にある作業フォルダ全体を `git add .` しないでください。** 旧開発物や実データ入りの検証ログがある環境では、とくに公開用フォルダだけを使います。

## GitHubへアップロード

GitHubで、自分のアカウントに空の `qites-xml-loader` リポジトリを作成します。GitHub側でREADME・LICENSEを同時生成せず、確認済みの公開用ソースフォルダで次を実行してください。

```powershell
git init -b main
git add .
git diff --cached --stat
git diff --cached
git commit -m "Initial public release"
git remote add origin https://github.com/YOUR_ACCOUNT/qites-xml-loader.git
git push -u origin main
```

`YOUR_ACCOUNT` を自分のアカウント名へ置き換えます。認証はGitHub CLIやGit Credential Managerなどの通常の方法を使い、トークンをソースやコマンド例に書き込みません。GitHub Desktopで公開用フォルダを追加してPublishする方法でも構いません。

公開ソースに `.github/workflows/build.yml` があるため、push後にActionsでWindowsビルドと合成データのテストが動きます。CIは実音声デバイスの聴感確認や全形式の変換保証にはなりません。

## Releasesでインストーラーを配る

1. GitHubの「Releases」→「Draft a new release」。タグ例は `v0.9`。
2. 検証済みの `QitesXmlLoader-Setup-0.9.exe`、`QitesXmlLoader-0.9-win-x64.zip`、チェックサムを添付します。ソースの履歴にビルド済みEXEを入れる必要はありません。
3. `docs/RELEASE_NOTES.md` を基に説明を書き、初回はpre-releaseとして公開する方法もあります。
4. 説明には「FFmpeg別途インストール」「Windows x64」「読み取り専用」「スマートはXML保存時点」「未署名」「非公式アプリ」を明記します。

FUNDING.ymlは `paypal.me/tadanomat` へリンクします。寄付はAIによる参照・引用・フォークの目安を知るための任意のお願いで、手動フォークの条件ではありません。寄付金控除用の証明書を発行するものでもありません。

## 公式資料

- [ローカルコードをGitHubへ追加](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
- [リポジトリのライセンス](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [Releasesの作成](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Secret scanning](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/detect-secret-leaks/enable-secret-scanning)
- [Appleの商標ガイドライン](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
- [Appleの商標一覧](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
- [FFmpegのライセンス案内](https://ffmpeg.org/legal.html)
