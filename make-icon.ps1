# Tạo icon.ico cho DUOCNC DevOps Panel (nhiều kích thước, PNG bên trong ICO)
Add-Type -AssemblyName System.Drawing
$out   = Join-Path $PSScriptRoot 'icon.ico'
$sizes = 16, 24, 32, 48, 64, 128, 256

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

$pngs = foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    # Nền: bo góc, gradient xanh đậm
    $pad = [Math]::Max(1, $s * 0.04)
    $rect = New-RoundRect $pad $pad ($s - 2 * $pad) ($s - 2 * $pad) ($s * 0.22)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        [System.Drawing.PointF]::new(0, 0), [System.Drawing.PointF]::new($s, $s),
        [System.Drawing.Color]::FromArgb(255, 37, 99, 235), [System.Drawing.Color]::FromArgb(255, 15, 23, 42))
    $g.FillPath($bg, $rect)

    # Ký hiệu terminal ">_"
    $w = [Math]::Max(1.6, $s * 0.10)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 74, 222, 128), $w)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($s * 0.24, $s * 0.32),
        [System.Drawing.PointF]::new($s * 0.44, $s * 0.50),
        [System.Drawing.PointF]::new($s * 0.24, $s * 0.68)))
    $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $w)
    $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'
    $g.DrawLine($pen2, $s * 0.52, $s * 0.70, $s * 0.76, $s * 0.70)

    # Chấm trạng thái (bỏ ở cỡ nhỏ cho đỡ rối)
    if ($s -ge 32) {
        $dr = $s * 0.13
        $g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 74, 222, 128))),
            [float]($s * 0.80 - $dr), [float]($s * 0.20), [float]($dr * 2), [float]($dr * 2))
    }

    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

# Ghi file ICO: header + directory + dữ liệu PNG
$fs = [System.IO.File]::Create($out)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256))
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$len); $bw.Write([UInt32]$offset)
    $offset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close()

# Bản PNG lớn để xem trước
[System.IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'icon-preview.png'), $pngs[-1])
"Đã tạo $out"
