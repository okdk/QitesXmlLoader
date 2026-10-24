$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$cache=Join-Path $root '.dependencies';$lib=Join-Path $root 'src/lib'
[IO.Directory]::CreateDirectory($cache) | Out-Null
[IO.Directory]::CreateDirectory($lib) | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$packages=@(
 @{Name='NAudio.Core';Hash='794645DBFD30E4880663D52D9D9224D55C301FA54228FF623C95D572C7887347'},
 @{Name='NAudio.Wasapi';Hash='C8396B8DBAB86A2619EDFD9158BEAF18C21CB86677099B5594950FD8651B9D1A'}
)
foreach($package in $packages){
 $id=$package.Name.ToLowerInvariant();$file=Join-Path $cache ($id+'.2.2.1.nupkg')
 if(-not [IO.File]::Exists($file)){
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $url="https://api.nuget.org/v3-flatcontainer/$id/2.2.1/$id.2.2.1.nupkg"
  if(Get-Command curl.exe -ErrorAction SilentlyContinue){
   & curl.exe -fL --connect-timeout 15 --max-time 45 --retry 1 -o $file $url
   if($LASTEXITCODE -ne 0){throw ('Dependency download failed: '+$package.Name)}
  }else{Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file -TimeoutSec 45}
 }
 if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $package.Hash){throw ('Dependency checksum mismatch: '+$package.Name)}
 $archive=[IO.Compression.ZipFile]::OpenRead($file)
 try{
  $entry=$archive.GetEntry(('lib/netstandard2.0/'+$package.Name+'.dll'))
  if($null -eq $entry){throw 'Dependency assembly missing'}
  $input=$entry.Open();$memory=New-Object IO.MemoryStream
  try{$input.CopyTo($memory)}finally{$input.Dispose()}
  $path=Join-Path $lib ($package.Name+'.dll');$bytes=$memory.ToArray();$memory.Dispose()
  if([IO.File]::Exists($path)){
   $sha=[Security.Cryptography.SHA256]::Create();try{$expected=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
   if((Get-FileHash -LiteralPath $path).Hash -ne $expected){throw ('Existing dependency differs: '+$path)}
  }else{[IO.File]::WriteAllBytes($path,$bytes)}
 }finally{$archive.Dispose()}
}
