function Read-AppSettings {
 param([string]$Path)
 $saved=$null
 $values=@{Language=$(if([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ja'){'ja'}else{'en'});OutputDeviceId='';FFmpegPath='';MissingPolicy='Stop';ResolveLibraryNames=$false;AllowNetworkPaths=$false;SourceLoader='itunes';SourcePath='';LastFileDecision='No'}
 if([IO.File]::Exists($Path)){
  try{$saved=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json;foreach($name in @('Language','OutputDeviceId','FFmpegPath','MissingPolicy','SourceLoader','SourcePath','LastFileDecision')){if($saved.PSObject.Properties.Name -contains $name){$values[$name]=[string]$saved.$name}};if($saved.PSObject.Properties.Name -contains 'ResolveLibraryNames'){$values.ResolveLibraryNames=$saved.ResolveLibraryNames -eq $true}}catch{}
 }
 if($saved -and $null -ne $saved.PSObject.Properties['AllowNetworkPaths']){$values.AllowNetworkPaths=$saved.AllowNetworkPaths -eq $true}
 if($values.Language -notin @('ja','en')){$values.Language='ja'}
 if($values.MissingPolicy -notin @('Stop','Skip')){$values.MissingPolicy='Stop'}
 return $values
}
function Save-AppSettings {
 param([string]$Path,[hashtable]$Values)
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temp,($Values | ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
 if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Resolve-FFmpeg {
 param([string]$ConfiguredPath)
 if(-not [string]::IsNullOrWhiteSpace($ConfiguredPath)){
  $candidate=$ConfiguredPath.Trim().Trim('"')
  try{Assert-AllowedPath $candidate}catch{return $null}
  if([IO.Directory]::Exists($candidate)){
   $direct=Join-Path $candidate 'ffmpeg.exe'
   $candidate=$(if([IO.File]::Exists($direct)){$direct}else{Join-Path $candidate 'bin/ffmpeg.exe'})
  }
  if([IO.File]::Exists($candidate) -and [IO.Path]::GetFileName($candidate) -ieq 'ffmpeg.exe'){return [IO.Path]::GetFullPath($candidate)}
  return $null
 }
 $command=Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue
 if($command){return $command.Source}
 return $null
}
