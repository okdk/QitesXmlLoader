$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path $PSScriptRoot -Parent
$assets=Join-Path $root 'assets';[IO.Directory]::CreateDirectory($assets) | Out-Null
$images=New-Object 'System.Collections.Generic.List[byte[]]'
foreach($size in @(16,24,32,48,64,128,256)){
 $bitmap=New-Object Drawing.Bitmap(512,512)
 $g=[Drawing.Graphics]::FromImage($bitmap);$g.SmoothingMode='AntiAlias';$g.Clear([Drawing.Color]::Transparent)
 $navy=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#12263A'))
 $white=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F4FAFF'))
 $teal=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#29D7C1'))
 $g.FillEllipse($navy,8,8,496,496)
 $g.FillRectangle($white,112,76,220,314)
 $g.FillPolygon($navy,[Drawing.Point[]]@((New-Object Drawing.Point(278,76)),(New-Object Drawing.Point(332,130)),(New-Object Drawing.Point(332,76))))
 $pen=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#12263A'),18);$pen.StartCap='Round';$pen.EndCap='Round';$pen.LineJoin='Round'
 $g.DrawLines($pen,[Drawing.Point[]]@((New-Object Drawing.Point(174,176)),(New-Object Drawing.Point(145,205)),(New-Object Drawing.Point(174,234))))
 $g.DrawLines($pen,[Drawing.Point[]]@((New-Object Drawing.Point(228,176)),(New-Object Drawing.Point(257,205)),(New-Object Drawing.Point(228,234))))
 $g.DrawLine($pen,213,170,190,240)
 $g.FillEllipse($navy,231,242,204,204)
 $g.FillEllipse($teal,251,328,62,45);$g.FillEllipse($teal,347,306,62,45)
 $g.FillRectangle($teal,296,272,17,78);$g.FillRectangle($teal,392,250,17,78)
 $g.FillPolygon($teal,[Drawing.Point[]]@((New-Object Drawing.Point(296,272)),(New-Object Drawing.Point(409,246)),(New-Object Drawing.Point(409,271)),(New-Object Drawing.Point(296,297))))
 $small=New-Object Drawing.Bitmap($size,$size);$sg=[Drawing.Graphics]::FromImage($small);$sg.InterpolationMode='HighQualityBicubic';$sg.DrawImage($bitmap,0,0,$size,$size)
 $memory=New-Object IO.MemoryStream;$small.Save($memory,[Drawing.Imaging.ImageFormat]::Png);$images.Add($memory.ToArray())
 if($size -eq 256){$small.Save((Join-Path $assets 'QitesXmlLoader.png'),[Drawing.Imaging.ImageFormat]::Png)}
 $memory.Dispose();$sg.Dispose();$small.Dispose();$pen.Dispose();$navy.Dispose();$white.Dispose();$teal.Dispose();$g.Dispose();$bitmap.Dispose()
}
$file=[IO.File]::Create((Join-Path $assets 'QitesXmlLoader.ico'));$writer=New-Object IO.BinaryWriter($file)
try{
 $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
 $offset=6+16*$images.Count;$index=0
 foreach($size in @(16,24,32,48,64,128,256)){
  $value=$(if($size -eq 256){0}else{$size});$writer.Write([byte]$value);$writer.Write([byte]$value);$writer.Write([byte]0);$writer.Write([byte]0)
  $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$images[$index].Length);$writer.Write([uint32]$offset);$offset+=$images[$index].Length;$index++
 }
 foreach($data in $images){$writer.Write($data)}
}finally{$writer.Dispose();$file.Dispose()}
