function Write-UnlinkKit {
 param([string]$Root,[object[]]$Records,[QitesXmlLoader.Operation]$Operation)
 if(-not $Records.Count){return}
 $kit='unlink-'+[guid]::NewGuid().ToString('N');$directory=Join-Path $Root $kit;$Operation.MakeDirectory($directory)
 $entries=New-Object 'System.Collections.Generic.List[object]'
 foreach($record in $Records){
  $Operation.Check();[QitesXmlLoader.Native]::NoRedirect($record.Output)
  $identity=[QitesXmlLoader.Native]::Identity($record.Output)
  if($identity -ne [QitesXmlLoader.Native]::Identity($record.Source)){throw (T '作成したハードリンクの同一性を確認できません。')}
  $entries.Add([pscustomobject]@{RelativePath=$record.Output.Substring($Root.Length+1);Source=$record.Source;Identity=$identity})
 }
 $manifest=[pscustomobject]@{Version=1;RootIdentity=[QitesXmlLoader.Native]::Identity($Root);Entries=$entries.ToArray()}
 $Operation.WriteText((Join-Path $directory 'manifest.json'),($manifest | ConvertTo-Json -Depth 6))
 $helper=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Unlink-Hardlinks.ps1'))
 $Operation.WriteText((Join-Path $directory 'Unlink-Hardlinks.ps1'),[char]0xFEFF+$helper.TrimStart([char]0xFEFF))
 $networkFlag=if($script:AllowNetworkPaths){' -AllowNetwork'}else{''}
 $batch="@echo off`r`nsetlocal DisableDelayedExpansion`r`n"+'"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0'+$kit+'\Unlink-Hardlinks.ps1" -Interactive'+$networkFlag+"`r`n"+'set "qitesExit=%ERRORLEVEL%"'+"`r`npause`r`nexit /b %qitesExit%`r`n"
 $Operation.WriteText((Join-Path $Root ('UNLINK-'+$kit+'.bat')),$batch)
 $Operation.WriteText((Join-Path $directory 'README.txt'),(T '解除BATは生成したリンクだけを確認し、UNLINKと入力した場合だけ解除します。元ファイルがない、IDが違う、リンク数が2未満、範囲外、再解析ポイントの場合は拒否します。コピーした通常ファイルは解除対象にしません。作業中は元ファイルの移動・削除を行わないでください。完全な安全を保証するものではありません。詳細はdocs/UNLINK.mdを参照してください。'))
}
