function T {
 param([string]$Key,[object[]]$Values=@())
 return [QitesXmlLoader.Text]::Get($Key,$Values)
}
function Set-AppLanguage {
 param([ValidateSet('ja','en')][string]$Language)
 $path=Join-Path $PSScriptRoot ('i18n/'+$Language+'.json')
 [QitesXmlLoader.Text]::Load($path)
 $script:locale=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
function Resolve-AppFont {
 param([string]$Requested)
 if(-not [string]::IsNullOrWhiteSpace($Requested)){
  foreach($name in $Requested.Split(',')){
   $match=[Windows.Media.Fonts]::SystemFontFamilies | Where-Object {$_.Source -ieq $name.Trim()} | Select-Object -First 1
   if($match){return $match}
  }
 }
 return [Windows.SystemFonts]::MessageFontFamily
}
function Initialize-LocalizedMarkup {
 param([xml]$Document)
 $script:localizationBindings=New-Object 'System.Collections.Generic.List[object]'
 $index=0
 foreach($node in $Document.SelectNodes('//*')){
  foreach($property in @('Text','Content','Header','ToolTip')){
   if($node.HasAttribute($property)){
    $key=$node.GetAttribute($property)
    if($script:locale.Strings.PSObject.Properties.Name -contains $key){
     $name=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
     if(-not $name){
      $index++;$name='Localized'+$index
      $attribute=$Document.CreateAttribute('x','Name','http://schemas.microsoft.com/winfx/2006/xaml');$attribute.Value=$name
      [void]$node.Attributes.Append($attribute)
     }
     $script:localizationBindings.Add([pscustomobject]@{Name=$name;Property=$property;Key=$key})
     $node.SetAttribute($property,(T $key))
    }
   }
  }
 }
}
function Apply-AppLanguage {
 foreach($binding in $script:localizationBindings){$element=$window.FindName($binding.Name);if($null -ne $element){$element.($binding.Property)=T $binding.Key}}
 $uiFont=$null;$codeFont=$null
 if($script:locale.PSObject.Properties.Name -contains 'Fonts'){
  if($script:locale.Fonts.PSObject.Properties.Name -contains 'Ui'){$uiFont=[string]$script:locale.Fonts.Ui}
  if($script:locale.Fonts.PSObject.Properties.Name -contains 'Code'){$codeFont=[string]$script:locale.Fonts.Code}
 }
 $window.FontFamily=Resolve-AppFont $uiFont
 $ui.Options.FontFamily=Resolve-AppFont $codeFont
 $window.Title='Qites xml loader'
}
