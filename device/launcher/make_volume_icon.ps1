Add-Type -AssemblyName System.Drawing
$out = ".\out"
New-Item -ItemType Directory -Force $out | Out-Null
$S = 192
$bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
# rounded-square background (blue), like a normal app icon
$r = 44
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(0, 0, 2*$r, 2*$r, 180, 90); $path.AddArc($S-2*$r, 0, 2*$r, 2*$r, 270, 90)
$path.AddArc($S-2*$r, $S-2*$r, 2*$r, 2*$r, 0, 90); $path.AddArc(0, $S-2*$r, 2*$r, 2*$r, 90, 90); $path.CloseFigure()
$g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 26, 115, 232))), $path)
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
# speaker: small rectangle + cone
$pts = @(
  (New-Object System.Drawing.PointF 40, 78), (New-Object System.Drawing.PointF 66, 78),
  (New-Object System.Drawing.PointF 98, 50), (New-Object System.Drawing.PointF 98, 142),
  (New-Object System.Drawing.PointF 66, 114), (New-Object System.Drawing.PointF 40, 114))
$g.FillPolygon($white, [System.Drawing.PointF[]]$pts)
# sound waves
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 9
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($pen, 94, 66, 36, 60, -55, 110)
$g.DrawArc($pen, 94, 46, 66, 100, -55, 110)
$g.Dispose()
$bmp.Save("$out\volume_icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"wrote $out\volume_icon.png"
