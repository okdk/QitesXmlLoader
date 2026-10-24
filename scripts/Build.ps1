param([switch]$SkipRestore)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $SkipRestore){& (Join-Path $PSScriptRoot 'Restore-Dependencies.ps1')}
& (Join-Path $PSScriptRoot 'Build-Icon.ps1')
$src=(Resolve-Path (Join-Path $root 'src')).Path
$build=Join-Path $root ('build/app-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$dist=Join-Path $root 'dist'
[IO.Directory]::CreateDirectory($build) | Out-Null
[IO.Directory]::CreateDirectory($dist) | Out-Null
Get-ChildItem -LiteralPath $src -Filter *.ps1 | ForEach-Object {
 $body=[IO.File]::ReadAllText($_.FullName)
 [IO.File]::WriteAllText((Join-Path $build $_.Name),$body,(New-Object Text.UTF8Encoding($true)))
}
Copy-Item -LiteralPath (Join-Path $src 'startup.wav'),(Join-Path $src 'QitesXmlLoader.exe.config') -Destination $build
Copy-Item -LiteralPath (Join-Path $src 'i18n'),(Join-Path $src 'loaders') -Destination $build -Recurse
Get-ChildItem (Join-Path $build 'loaders') -Filter *.ps1 | ForEach-Object {[IO.File]::WriteAllText($_.FullName,[IO.File]::ReadAllText($_.FullName),(New-Object Text.UTF8Encoding($true)))}
Copy-Item -LiteralPath (Join-Path $root 'assets') -Destination $build -Recurse
$lib=Join-Path $build 'lib';[IO.Directory]::CreateDirectory($lib) | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'lib/NAudio.Core.dll'),(Join-Path $src 'lib/NAudio.Wasapi.dll'),(Join-Path $src 'lib/NAudio-LICENSE.txt') -Destination $lib
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$netstandard=(Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/netstandard') -Filter netstandard.dll -Recurse | Select-Object -First 1).FullName
$automation=(Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation') -Filter System.Management.Automation.dll -Recurse | Select-Object -First 1).FullName
$sources=@('Runtime.cs','XmlCache.cs','Audio.cs','I18n.cs','PlaylistNode.cs') | ForEach-Object {Join-Path $src $_}
& $csc /nologo /target:library /platform:x64 /reference:System.Web.Extensions.dll /reference:System.Xml.dll /reference:System.Core.dll ("/reference:"+$netstandard) ("/reference:"+(Join-Path $lib 'NAudio.Core.dll')) ("/reference:"+(Join-Path $lib 'NAudio.Wasapi.dll')) ("/out:"+(Join-Path $lib 'QitesXmlLoader.Runtime.dll')) @sources
if($LASTEXITCODE){throw 'Runtime compilation failed'}
$icon=(Resolve-Path (Join-Path $root 'assets/QitesXmlLoader.ico')).Path
$manifest=(Resolve-Path (Join-Path $PSScriptRoot 'app.manifest')).Path
& $csc /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll ("/reference:"+$automation) ("/reference:"+(Join-Path $lib 'QitesXmlLoader.Runtime.dll')) ("/win32icon:"+$icon) ("/win32manifest:"+$manifest) ("/out:"+(Join-Path $build 'QitesXmlLoader.exe')) (Join-Path $src 'Launcher.cs') (Join-Path $src 'AssemblyInfo.cs')
if($LASTEXITCODE){throw 'Application compilation failed'}
foreach($name in @('README.md','README.en.md','LICENSE','THIRD-PARTY.md','NOTICE.md')){if(Test-Path -LiteralPath (Join-Path $root $name)){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $build}}
if(Test-Path -LiteralPath (Join-Path $root 'examples')){Copy-Item -LiteralPath (Join-Path $root 'examples') -Destination $build -Recurse}
if(Test-Path -LiteralPath (Join-Path $root 'docs')){Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $build -Recurse}
$bundle=Join-Path $root ('build/bundle-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($bundle) | Out-Null
Copy-Item -LiteralPath $build -Destination (Join-Path $bundle 'QitesXmlLoader') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install.ps1') -Destination $bundle
$zip=Join-Path $dist 'QitesXmlLoader-0.9-win-x64.zip'
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -Force
& $csc /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.IO.Compression.FileSystem.dll ("/win32icon:"+$icon) ("/win32manifest:"+$manifest) ("/resource:"+$zip+',payload.zip') ("/out:"+(Join-Path $dist 'QitesXmlLoader-Setup-0.9.exe')) (Join-Path $PSScriptRoot 'Setup.cs') (Join-Path $src 'AssemblyInfo.cs')
if($LASTEXITCODE){throw 'Installer compilation failed'}
$result=[pscustomobject]@{Version='0.9';AppRoot=$build;Zip=$zip;Setup=(Join-Path $dist 'QitesXmlLoader-Setup-0.9.exe');FFmpegBundled=$false}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'build/latest.json') -Encoding UTF8
$result | ConvertTo-Json
