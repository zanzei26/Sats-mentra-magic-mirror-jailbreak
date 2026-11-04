Add-Type -AssemblyName System.Drawing
$out = ".\out"
New-Item -ItemType Directory -Force $out | Out-Null
$W = 240
$bmp = New-Object System.Drawing.Bitmap $W, $W, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Black)
$white = [System.Drawing.Color]::White
$grey = [System.Drawing.Color]::FromArgb(255, 140, 140, 140)

# mirror: oval frame (thick outer, thin inner)
$pen = New-Object System.Drawing.Pen $white, 5
$g.DrawEllipse($pen, 76, 12, 88, 128)
$pen2 = New-Object System.Drawing.Pen $grey, 1.5
$g.DrawEllipse($pen2, 85, 21, 70, 110)
# glint on the glass (two diagonal strokes, upper left)
$pg = New-Object System.Drawing.Pen $white, 4
$pg.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $pg.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($pg, 100, 62, 124, 36)
$pg2 = New-Object System.Drawing.Pen $white, 2.5
$pg2.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $pg2.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($pg2, 100, 80, 112, 67)

# magic sparkles (4-point stars)
function Star($cx, $cy, $ro, $ri) {
  $pts = @()
  for ($i = 0; $i -lt 8; $i++) {
    $a = [Math]::PI / 2 * ($i / 2.0) + [Math]::PI / 4 * 0
    $r = if ($i % 2 -eq 0) { $ro } else { $ri }
    $ang = [Math]::PI / 4 * $i - [Math]::PI / 2
    $pts += New-Object System.Drawing.PointF ([single]($cx + $r * [Math]::Cos($ang))), ([single]($cy + $r * [Math]::Sin($ang)))
  }
  $script:g.FillPolygon((New-Object System.Drawing.SolidBrush $script:white), [System.Drawing.PointF[]]$pts)
}
Star 192 44 16 4
Star 54 104 9 2.5
Star 196 100 6 1.8

# text
$font = New-Object System.Drawing.Font('Segoe UI Semibold', 25, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = New-Object System.Drawing.SolidBrush $white
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$m = $g.MeasureString('MAGIC MIRROR', $font)
"text width: $([int]$m.Width) px (canvas 240)"
$g.DrawString('MAGIC MIRROR', $font, $brush, (New-Object System.Drawing.RectangleF 0, 166, 240, 44), $sf)
$g.Dispose()
$bmp.Save("$out\design.png", [System.Drawing.Imaging.ImageFormat]::Png)

# raw top-down luminance (R channel; the design is monochrome) for the BMP builder
$raw = New-Object byte[] ($W * $W)
for ($y = 0; $y -lt $W; $y++) { for ($x = 0; $x -lt $W; $x++) { $raw[$y * $W + $x] = $bmp.GetPixel($x, $y).R } }
[System.IO.File]::WriteAllBytes("$out\design_gray.raw", $raw)
$bmp.Dispose()
"wrote design.png and design_gray.raw"
