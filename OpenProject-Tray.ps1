#Requires -Version 5.1
# OpenProject tray UI — WSL/start/stop on a background Runspace (UI never blocks).
# Save as UTF-8 with BOM for PowerShell 5.1 + Cyrillic.
param([switch]$Background, [switch]$Startup)
$ErrorActionPreference = 'Stop'
trap {
    try {
        $errorDir = Join-Path $PSScriptRoot 'logs'
        [void][System.IO.Directory]::CreateDirectory($errorDir)
        [System.IO.File]::AppendAllText((Join-Path $errorDir 'tray-startup-error.log'), ($_ | Out-String))
    } catch { }
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:TrayDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:TrayDir 'OpenProject-Tray.Core.ps1')
Initialize-OpenProjectTrayCore -TrayDir $script:TrayDir
. (Join-Path $script:TrayDir 'OpenProject-Tray.Desktop.ps1')

$script:Busy = $false
$script:BgPowerShell = $null
$script:BgHandle = $null
$script:BgActionName = $null
$script:TrayState = 'Stopped'
$script:LastErrorTip = $null
$script:BusyStartedAt = $null
$script:StatusIcons = @{}
$script:BaseIcon = $null
$script:OwnedStatusIcons = @()
$script:IconStreams = @()
$script:BaseIconPath = $null
$script:MenuStatusItem = $null
$script:StatusMenuImages = @{}
$script:OwnedStatusMenuImages = @()

function Get-OpUiTheme {
    return @{
        # OpenProject design system: Main #1A67A3, Info/edge #8FC0DB, Focus #00A3FF
        Brand       = [System.Drawing.Color]::FromArgb(255, 26, 103, 163)
        BrandDark   = [System.Drawing.Color]::FromArgb(255, 18, 78, 128)
        Edge        = [System.Drawing.Color]::FromArgb(255, 143, 192, 219)
        EdgeSoft    = [System.Drawing.Color]::FromArgb(255, 190, 220, 236)
        Surface     = [System.Drawing.Color]::FromArgb(255, 246, 249, 252)
        Panel       = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        Border      = [System.Drawing.Color]::FromArgb(255, 190, 220, 236)
        Text        = [System.Drawing.Color]::FromArgb(255, 51, 51, 51)
        Muted       = [System.Drawing.Color]::FromArgb(255, 135, 135, 135)
        LogBg       = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        LogFg       = [System.Drawing.Color]::FromArgb(255, 51, 51, 51)
        MenuBg      = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        MenuHover   = [System.Drawing.Color]::FromArgb(255, 227, 245, 255)
        BtnPrimary  = [System.Drawing.Color]::FromArgb(255, 26, 103, 163)
        BtnPrimaryText = [System.Drawing.Color]::White
        BtnGhost    = [System.Drawing.Color]::FromArgb(255, 243, 248, 252)
        RadiusForm  = 14
        RadiusMenu  = 12
        RadiusCard  = 10
        RadiusBtn   = 8
        FontUi      = New-Object System.Drawing.Font('Segoe UI', 9.5)
        FontUiBold  = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        FontTitle   = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        FontMono    = $null
        FontMonoFallback = New-Object System.Drawing.Font('Consolas', 9.25)
    }
}

if (-not ([System.Management.Automation.PSTypeName]'OpTray.UiShape').Type) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace OpTray {
  public static class UiShape {
    public static GraphicsPath RoundedRect(Rectangle bounds, int radius) {
      int r = Math.Max(1, Math.Min(radius, Math.Min(bounds.Width, bounds.Height) / 2));
      int d = r * 2;
      GraphicsPath path = new GraphicsPath();
      path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
      path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
      path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
      path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
      path.CloseFigure();
      return path;
    }
  }
  public class UiMenuColorTable : ProfessionalColorTable {
    public override Color MenuItemSelected { get { return Color.FromArgb(227, 245, 255); } }
    public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(227, 245, 255); } }
    public override Color MenuItemSelectedGradientEnd { get { return Color.FromArgb(227, 245, 255); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(143, 192, 219); } }
    public override Color MenuBorder { get { return Color.FromArgb(143, 192, 219); } }
    public override Color ToolStripDropDownBackground { get { return Color.White; } }
    public override Color ImageMarginGradientBegin { get { return Color.White; } }
    public override Color ImageMarginGradientMiddle { get { return Color.White; } }
    public override Color ImageMarginGradientEnd { get { return Color.White; } }
    public override Color SeparatorDark { get { return Color.FromArgb(190, 220, 236); } }
    public override Color SeparatorLight { get { return Color.FromArgb(246, 249, 252); } }
  }
  public class UiMenuRenderer : ToolStripProfessionalRenderer {
    public UiMenuRenderer() : base(new UiMenuColorTable()) { }
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
      Rectangle r = new Rectangle(0, 0, e.ToolStrip.Width, e.ToolStrip.Height);
      using (GraphicsPath path = UiShape.RoundedRect(r, 12))
      using (SolidBrush brush = new SolidBrush(Color.White)) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.FillPath(brush, path);
      }
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
      Rectangle r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
      using (GraphicsPath path = UiShape.RoundedRect(r, 12))
      using (Pen pen = new Pen(Color.FromArgb(143, 192, 219), 1.6f)) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawPath(pen, path);
      }
    }
  }
}
"@
}

function Update-OpRoundedRegion {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 12
    )
    if ($Control.Width -lt 4 -or $Control.Height -lt 4) { return }
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Control.Width, $Control.Height
    $path = [OpTray.UiShape]::RoundedRect($rect, $Radius)
    $old = $Control.Region
    $Control.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
    if ($old) { try { $old.Dispose() } catch { } }
}

function Enable-OpRoundedChrome {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 12,
        [System.Drawing.Color]$BorderColor = [System.Drawing.Color]::Empty,
        [float]$BorderWidth = 1.6
    )
    if ($BorderColor.IsEmpty) {
        $BorderColor = (Get-OpUiTheme).Edge
    }
    $Control.Tag = @{
        OpRadius = $Radius
        OpBorder = $BorderColor
        OpBorderWidth = $BorderWidth
    }
    $apply = {
        $c = $this
        $tag = $c.Tag
        if (-not $tag -or -not $tag.OpRadius) { return }
        Update-OpRoundedRegion -Control $c -Radius ([int]$tag.OpRadius)
        $c.Invalidate()
    }
    $paint = {
        param($sender, $e)
        $tag = $sender.Tag
        if (-not $tag -or -not $tag.OpBorder) { return }
        $r = New-Object System.Drawing.Rectangle 0, 0, ($sender.Width - 1), ($sender.Height - 1)
        $path = [OpTray.UiShape]::RoundedRect($r, [int]$tag.OpRadius)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]$tag.OpBorder), ([float]$tag.OpBorderWidth)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
        $path.Dispose()
    }
    $Control.Add_Resize($apply)
    $Control.Add_SizeChanged($apply)
    $Control.Add_Paint($paint)
    Update-OpRoundedRegion -Control $Control -Radius $Radius
}

function Enable-OpFormDrag {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Handle,
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form
    )
    $Handle.Tag = @{ DragForm = $Form }
    $Handle.Add_MouseDown({
        param($s, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $f = $s.Tag.DragForm
        if (-not $f) { return }
        $script:OpDragActive = $true
        $script:OpDragForm = $f
        $pt = [System.Windows.Forms.Cursor]::Position
        $script:OpDragDX = $pt.X - $f.Left
        $script:OpDragDY = $pt.Y - $f.Top
    })
    $Handle.Add_MouseMove({
        param($s, $e)
        if (-not $script:OpDragActive) { return }
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            $script:OpDragActive = $false
            return
        }
        $pt = [System.Windows.Forms.Cursor]::Position
        $script:OpDragForm.Location = New-Object System.Drawing.Point(($pt.X - $script:OpDragDX), ($pt.Y - $script:OpDragDY))
    })
    $Handle.Add_MouseUp({ $script:OpDragActive = $false })
}

function Get-OpMonoFont {
    param($Theme)
    if ($Theme.FontMono) { return $Theme.FontMono }
    foreach ($name in @('Cascadia Mono', 'Cascadia Code', 'Consolas')) {
        try {
            return New-Object System.Drawing.Font($name, 9.25)
        } catch { }
    }
    return $Theme.FontMonoFallback
}

function New-OpDialogShell {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Subtitle,
        [int]$Width = 720,
        [int]$Height = 520,
        [switch]$Fixed
    )
    $t = Get-OpUiTheme
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'None'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.BackColor = $t.Edge
    $form.Padding = New-Object System.Windows.Forms.Padding(2)
    $form.Font = $t.FontUi
    $form.ForeColor = $t.Text
    $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min(520, $Width), [Math]::Min(360, $Height))
    $form.ClientSize = New-Object System.Drawing.Size($Width, $Height)
    try {
        $prop = $form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic')
        if ($prop) { $prop.SetValue($form, $true, $null) }
    } catch { }
    Enable-OpRoundedChrome -Control $form -Radius $t.RadiusForm -BorderColor $t.Brand -BorderWidth 1.8

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 58
    $header.BackColor = $t.Brand
    $header.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    $form.Controls.Add($header)
    Enable-OpFormDrag -Handle $header -Form $form

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.ForeColor = [System.Drawing.Color]::White
    $titleLbl.Font = $t.FontTitle
    $titleLbl.AutoSize = $true
    $titleLbl.Location = New-Object System.Drawing.Point(18, 10)
    $titleLbl.BackColor = [System.Drawing.Color]::Transparent
    $header.Controls.Add($titleLbl)
    Enable-OpFormDrag -Handle $titleLbl -Form $form

    $subLbl = New-Object System.Windows.Forms.Label
    $subLbl.Text = $Subtitle
    $subLbl.ForeColor = [System.Drawing.Color]::FromArgb(230, 255, 255, 255)
    $subLbl.Font = $t.FontUi
    $subLbl.AutoSize = $false
    $subLbl.Location = New-Object System.Drawing.Point(18, 34)
    $subLbl.Size = New-Object System.Drawing.Size(($Width - 70), 18)
    $subLbl.Anchor = 'Top,Left,Right'
    $subLbl.BackColor = [System.Drawing.Color]::Transparent
    $header.Controls.Add($subLbl)
    Enable-OpFormDrag -Handle $subLbl -Form $form

    $btnX = New-Object System.Windows.Forms.Button
    $btnX.Text = '✕'
    $btnX.Width = 32
    $btnX.Height = 28
    $btnX.FlatStyle = 'Flat'
    $btnX.FlatAppearance.BorderSize = 0
    $btnX.BackColor = $t.Brand
    $btnX.ForeColor = [System.Drawing.Color]::White
    $btnX.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnX.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnX.Anchor = 'Top,Right'
    $btnX.Location = New-Object System.Drawing.Point(($Width - 44), 14)
    $btnX.Tag = $form
    $btnX.Add_Click({
        param($s, $e)
        $f = $s.Tag
        if (-not $f) { return }
        $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $f.Close()
    })
    $header.Controls.Add($btnX)
    $form.CancelButton = $btnX

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 56
    $footer.BackColor = $t.Panel
    $footer.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
    $form.Controls.Add($footer)

    return @{
        Form     = $form
        Header   = $header
        Subtitle = $subLbl
        Footer   = $footer
        Theme    = $t
        CloseBtn = $btnX
    }
}

function New-OpDialogButton {
    param(
        [Parameter(Mandatory)][string]$Text,
        [switch]$Primary,
        [int]$Width = 104
    )
    $t = Get-OpUiTheme
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Width = $Width
    $btn.Height = 32
    $btn.FlatStyle = 'Flat'
    $btn.Font = $t.FontUi
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.FlatAppearance.BorderSize = 0
    if ($Primary) {
        $btn.BackColor = $t.BtnPrimary
        $btn.ForeColor = $t.BtnPrimaryText
        $btn.FlatAppearance.BorderSize = 0
    } else {
        $btn.BackColor = $t.BtnGhost
        $btn.ForeColor = $t.Text
        $btn.FlatAppearance.BorderColor = $t.Edge
        $btn.FlatAppearance.BorderSize = 1
    }
    Enable-OpRoundedChrome -Control $btn -Radius $t.RadiusBtn -BorderColor $(if ($Primary) { $t.BrandDark } else { $t.Edge }) -BorderWidth 1.2
    return $btn
}

function New-OpRoundedCard {
    param([System.Drawing.Color]$BackColor = [System.Drawing.Color]::Empty)
    $t = Get-OpUiTheme
    if ($BackColor.IsEmpty) { $BackColor = $t.LogBg }
    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor = $BackColor
    $card.Padding = New-Object System.Windows.Forms.Padding(12)
    Enable-OpRoundedChrome -Control $card -Radius $t.RadiusCard -BorderColor $t.Edge -BorderWidth 1.4
    return $card
}

function New-OpLogTextBox {
    param([string]$Text = '')
    $t = Get-OpUiTheme
    $tb = New-Object System.Windows.Forms.RichTextBox
    $tb.ReadOnly = $true
    $tb.DetectUrls = $false
    $tb.BorderStyle = 'None'
    $tb.Dock = 'Fill'
    $tb.Font = Get-OpMonoFont -Theme $t
    $tb.BackColor = $t.LogBg
    $tb.ForeColor = $t.LogFg
    $tb.WordWrap = $false
    $tb.HideSelection = $false
    $tb.Text = $Text
    return $tb
}

function Set-OpLogViewerToEnd {
    param([Parameter(Mandatory)]$Box)
    if (-not $Box) { return }
    try {
        $Box.SelectionStart = $Box.TextLength
        $Box.SelectionLength = 0
        $Box.ScrollToCaret()
    } catch { }
}

function Get-OpStateCaption {
    param([string]$State)
    switch ($State) {
        'Running'  { return 'Работает' }
        'Starting' { return 'Запуск…' }
        'Error'    { return 'Ошибка' }
        default    { return 'Остановлен' }
    }
}

function Get-OpStateColor {
    param([string]$State)
    # Same colors as tray badge pips
    switch ($State) {
        'Running'  { return [System.Drawing.Color]::FromArgb(255, 46, 204, 64) }
        'Starting' { return [System.Drawing.Color]::FromArgb(255, 240, 180, 20) }
        'Error'    { return [System.Drawing.Color]::FromArgb(255, 230, 50, 50) }
        default    { return [System.Drawing.Color]::FromArgb(255, 150, 150, 150) }
    }
}

function New-OpStatusDotImage {
    param(
        [Parameter(Mandatory)][System.Drawing.Color]$Color,
        [int]$Size = 16
    )
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $pad = 2
    $d = $Size - ($pad * 2)
    $fill = New-Object System.Drawing.SolidBrush $Color
    $g.FillEllipse($fill, $pad, $pad, $d, $d)
    $fill.Dispose()
    $ring = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 0, 0, 0)), 1
    $g.DrawEllipse($ring, $pad, $pad, $d - 1, $d - 1)
    $ring.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-OpTrayIconPixelSize {
    return 16
}

function Get-OpPngBitmapFromIco {
    param(
        [Parameter(Mandatory)][string]$IcoPath,
        [int]$PreferredSize = 256
    )
    # OpenProject.ico uses PNG frames; Icon.ToBitmap() corrupts them under .NET Framework.
    # Prefer the largest frame (default 256) and downscale — embedded 16/32 are soft.
    $bytes = [System.IO.File]::ReadAllBytes($IcoPath)
    if ($bytes.Length -lt 6) { throw "Invalid icon: $IcoPath" }
    $count = [BitConverter]::ToUInt16($bytes, 4)
    if ($count -lt 1) { throw "Icon has no images: $IcoPath" }

    $bestIdx = 0
    $bestW = -1
    $bestScore = [int]::MaxValue
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + ($i * 16)
        $w = [int]$bytes[$entry]
        if ($w -eq 0) { $w = 256 }
        $score = [Math]::Abs($w - $PreferredSize)
        # Prefer exact/near match; on ties take the larger frame
        if (($score -lt $bestScore) -or (($score -eq $bestScore) -and ($w -gt $bestW))) {
            $bestScore = $score
            $bestW = $w
            $bestIdx = $i
        }
    }
    $entry = 6 + ($bestIdx * 16)
    $size = [BitConverter]::ToUInt32($bytes, $entry + 8)
    $offset = [BitConverter]::ToUInt32($bytes, $entry + 12)
    if (($offset + $size) -gt $bytes.Length) { throw "Icon frame out of range: $IcoPath" }
    $frame = New-Object byte[] $size
    [Array]::Copy($bytes, [int]$offset, $frame, 0, [int]$size)
    $ms = New-Object System.IO.MemoryStream(,$frame)
    $img = $null
    try {
        $img = [System.Drawing.Image]::FromStream($ms, $true, $true)
        return New-Object System.Drawing.Bitmap($img)
    } finally {
        if ($img) { try { $img.Dispose() } catch { } }
        $ms.Dispose()
    }
}

function Convert-OpBitmapToIcon {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)
    # PNG-compressed .ico (Vista+) — preserves alpha.
    $pngMs = New-Object System.IO.MemoryStream
    $Bitmap.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $pngMs.ToArray()
    $pngMs.Dispose()

    $icoMs = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($icoMs)
    $bw.Write([uint16]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]1)
    $w = $Bitmap.Width
    $h = $Bitmap.Height
    if ($w -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$w) }
    if ($h -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$h) }
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$pngBytes.Length)
    $bw.Write([uint32]22)
    $bw.Write($pngBytes)
    $bw.Flush()
    $outBytes = $icoMs.ToArray()
    $bw.Dispose()

    $owned = New-Object System.IO.MemoryStream(,$outBytes)
    $script:IconStreams += $owned
    return New-Object System.Drawing.Icon($owned)
}

function New-OpBadgedIcon {
    param(
        [Parameter(Mandatory)][string]$IcoPath,
        [Parameter(Mandatory)][System.Drawing.Color]$BadgeColor,
        [int]$Size = 0
    )
    if ($Size -le 0) { $Size = Get-OpTrayIconPixelSize }

    $src = $null
    $bmp = $null
    try {
        $src = Get-OpPngBitmapFromIco -IcoPath $IcoPath -PreferredSize 256
        $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $rg = [System.Drawing.Graphics]::FromImage($bmp)
        $rg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $rg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $rg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $rg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $rg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $rg.Clear([System.Drawing.Color]::Transparent)
        $rg.DrawImage($src, 0, 0, $Size, $Size)
        $rg.Dispose()
        $src.Dispose(); $src = $null

        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        # ~55% of icon — readable status pip in a 16px tray
        $dot = [Math]::Max(8, [int][Math]::Floor($Size * 0.55))
        if ($dot -ge $Size) { $dot = $Size - 1 }
        $x = $Size - $dot
        $y = $Size - $dot
        $fill = New-Object System.Drawing.SolidBrush $BadgeColor
        $g.FillEllipse($fill, $x, $y, $dot, $dot)
        $fill.Dispose()
        $ring = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 0, 0, 0)), 1
        $g.DrawEllipse($ring, $x, $y, $dot - 1, $dot - 1)
        $ring.Dispose()
        $g.Dispose()

        return (Convert-OpBitmapToIcon -Bitmap $bmp)
    } finally {
        if ($src) { try { $src.Dispose() } catch { } }
        if ($bmp) { try { $bmp.Dispose() } catch { } }
    }
}

function Initialize-TrayIcons {
    $icoPath = Join-Path $script:TrayDir 'OpenProject.ico'
    $script:BaseIconPath = $icoPath
    $px = Get-OpTrayIconPixelSize
    try {
        $script:BaseIcon = New-Object System.Drawing.Icon($icoPath, $px, $px)
    } catch {
        $script:BaseIcon = New-Object System.Drawing.Icon($icoPath)
    }

    $colors = @{
        Running  = [System.Drawing.Color]::FromArgb(255, 46, 204, 64)
        Stopped  = [System.Drawing.Color]::FromArgb(255, 150, 150, 150)
        Starting = [System.Drawing.Color]::FromArgb(255, 240, 180, 20)
        Error    = [System.Drawing.Color]::FromArgb(255, 230, 50, 50)
    }
    $script:OwnedStatusIcons = @()
    $script:OwnedStatusMenuImages = @()
    $script:StatusMenuImages = @{}
    foreach ($state in @('Running', 'Stopped', 'Starting', 'Error')) {
        $ico = New-OpBadgedIcon -IcoPath $icoPath -BadgeColor $colors[$state] -Size $px
        $script:StatusIcons[$state] = $ico
        $script:OwnedStatusIcons += $ico
        $dot = New-OpStatusDotImage -Color $colors[$state] -Size 16
        $script:StatusMenuImages[$state] = $dot
        $script:OwnedStatusMenuImages += $dot
    }
}

function Dispose-TrayIcons {
    foreach ($ico in @($script:OwnedStatusIcons)) {
        try { if ($ico) { $ico.Dispose() } } catch { }
    }
    $script:OwnedStatusIcons = @()
    $script:StatusIcons = @{}
    foreach ($img in @($script:OwnedStatusMenuImages)) {
        try { if ($img) { $img.Dispose() } } catch { }
    }
    $script:OwnedStatusMenuImages = @()
    $script:StatusMenuImages = @{}
    try {
        if ($script:BaseIcon) { $script:BaseIcon.Dispose() }
    } catch { }
    $script:BaseIcon = $null
    foreach ($ms in @($script:IconStreams)) {
        try { if ($ms) { $ms.Dispose() } } catch { }
    }
    $script:IconStreams = @()
}

function Set-TrayTip {
    param([string]$Text)
    if ($null -eq $Text) { $Text = 'OpenProject' }
    if ($Text.Length -gt 60) { $Text = $Text.Substring(0, 57) + '...' }
    try { $script:NotifyIcon.Text = $Text } catch { }
}

function Set-TrayVisualState {
    param(
        [Parameter(Mandatory)][ValidateSet('Stopped', 'Starting', 'Running', 'Error')][string]$State,
        [string]$Tip = ''
    )
    $script:TrayState = $State
    if ($State -eq 'Error' -and $Tip) {
        $script:LastErrorTip = $Tip
    }
    if ($State -eq 'Running' -or $State -eq 'Stopped') {
        $script:LastErrorTip = $null
    }
    if ([string]::IsNullOrWhiteSpace($Tip)) {
        switch ($State) {
            'Running' { $Tip = 'OpenProject: Running' }
            'Stopped' { $Tip = 'OpenProject: Stopped' }
            'Starting' { $Tip = 'OpenProject: Starting...' }
            'Error' {
                if ($script:LastErrorTip) { $Tip = $script:LastErrorTip }
                else { $Tip = 'OpenProject: Error' }
            }
        }
    }
    Set-TrayTip $Tip
    try {
        $ico = $script:StatusIcons[$State]
        if ($ico) { $script:NotifyIcon.Icon = $ico }
    } catch { }
    if ($script:MenuStatusItem) {
        try {
            $script:MenuStatusItem.Text = Get-OpStateCaption -State $State
            $script:MenuStatusItem.ForeColor = Get-OpStateColor -State $State
            $img = $script:StatusMenuImages[$State]
            if ($img) { $script:MenuStatusItem.Image = $img }
        } catch { }
    }
}

function Show-Balloon {
    param(
        [string]$Title,
        [string]$Text,
        [System.Windows.Forms.ToolTipIcon]$Icon = 'Info'
    )
    if ([string]::IsNullOrEmpty($Text)) { $Text = '...' }
    if ($Text.Length -gt 200) { $Text = $Text.Substring(0, 197) + '...' }
    try {
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Text
        $script:NotifyIcon.BalloonTipIcon = $Icon
        $script:NotifyIcon.ShowBalloonTip(3500)
    } catch { }
}

function Set-MenuBusyState {
    param([bool]$Busy)
    $enabled = -not $Busy
    $script:MenuStart.Enabled = $enabled
    $script:MenuRestart.Enabled = $enabled
    $script:MenuRestartMigrate.Enabled = $enabled
    $script:MenuStop.Enabled = $enabled
    $script:MenuBrowser.Enabled = $enabled
    $script:MenuLogs.Enabled = $enabled
    $script:MenuDoctor.Enabled = $enabled
    $script:MenuTerminal.Enabled = $enabled
    $script:MenuPending.Enabled = $enabled
    $script:MenuSettings.Enabled = $enabled
}

function Update-TrayStatus {
    if ($script:Busy) { return }
    $running = $false
    try { $running = Test-OpenProjectQuick } catch { $running = $false }

    if ($running) {
        # Recover from Error badge if stack came up (or doctor left a stale Error).
        Set-TrayVisualState -State 'Running'
        $script:MenuStart.Enabled = $false
        $script:MenuStop.Enabled = $true
        $script:Timer.Interval = 10000
    } elseif ($script:TrayState -eq 'Error' -and $script:LastErrorTip) {
        Set-TrayVisualState -State 'Error' -Tip $script:LastErrorTip
        $script:MenuStart.Enabled = $true
        $script:MenuStop.Enabled = $false
        $script:Timer.Interval = 5000
    } else {
        Set-TrayVisualState -State 'Stopped'
        $script:MenuStart.Enabled = $true
        $script:MenuStop.Enabled = $false
        $script:Timer.Interval = 5000
    }
    $script:MenuRestart.Enabled = $true
    $script:MenuRestartMigrate.Enabled = $true
    $script:MenuBrowser.Enabled = $true
    $script:MenuLogs.Enabled = $true
    $script:MenuDoctor.Enabled = $true
    $script:MenuTerminal.Enabled = $true
    $script:MenuPending.Enabled = $true
    $script:MenuSettings.Enabled = $true
}

function Get-ActionLogLabel {
    param([string]$ActionName)
    switch ($ActionName) {
        'start' { return 'Старт' }
        'stop' { return 'Стоп' }
        'restart' { return 'Перезапуск' }
        'restart-migrate' { return 'Перезапуск + migrate' }
        'doctor' { return 'Проверка окружения' }
        'pending-migrate' { return 'Pending migrations' }
        default { return $ActionName }
    }
}

function Get-BgOpResult {
    param($Results)
    if ($null -eq $Results) { return $null }
    foreach ($item in @($Results)) {
        if ($item -is [hashtable] -or $item -is [System.Collections.IDictionary]) {
            return $item
        }
    }
    return $null
}

function Show-ReportDialog {
    param(
        [string]$Title,
        [string]$PathHint,
        [string]$Text
    )
    $shell = New-OpDialogShell -Title $Title -Subtitle $(if ($PathHint) { $PathHint } else { 'Отчёт' }) -Width 760 -Height 560
    $form = $shell.Form
    $footer = $shell.Footer
    $t = $shell.Theme

    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 8)
    $body.BackColor = $t.Surface
    $form.Controls.Add($body)
    $body.BringToFront()

    $card = New-OpRoundedCard -BackColor $t.LogBg
    $card.Dock = 'Fill'
    $body.Controls.Add($card)

    $tb = New-OpLogTextBox -Text $Text
    $card.Controls.Add($tb)

    $btnClose = New-OpDialogButton -Text 'Закрыть' -Primary
    $btnClose.Anchor = 'Top,Right'
    $btnClose.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 120), 12)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $footer.Controls.Add($btnClose)
    $form.CancelButton = $btnClose
    $footer.Add_Resize({
        $btnClose.Left = $footer.ClientSize.Width - 120
    })

    $script:OpReportLogBox = $tb
    $form.Add_Shown({
        Set-OpLogViewerToEnd -Box $script:OpReportLogBox
        if ($script:OpReportLogBox) { $script:OpReportLogBox.Focus() }
    })

    [void]$form.ShowDialog($script:HiddenForm)
    $script:OpReportLogBox = $null
    $form.Dispose()
}

function Complete-BackgroundOp {
    param($Ps, $Handle, $ActionName)
    $label = Get-ActionLogLabel -ActionName $ActionName
    try {
        $streams = $Ps.Streams
        $errMsgs = @($streams.Error | ForEach-Object { $_.ToString() })
        $results = $Ps.EndInvoke($Handle)
        $result = Get-BgOpResult -Results $results
        if ($errMsgs.Count -gt 0) {
            $err = ($errMsgs -join '; ')
            Write-OpActivityLog -Message "${label}: ошибка — $err"
            $tip = 'OpenProject: Error'
            if ($err.Length -gt 0) {
                $short = $err
                if ($short.Length -gt 40) { $short = $short.Substring(0, 37) + '...' }
                $tip = "OpenProject: $short"
            }
            Set-TrayVisualState -State 'Error' -Tip $tip
            Show-Balloon 'OpenProject' ("Ошибка: " + $err) 'Error'
        } elseif ($result -and $result.ContainsKey('Error') -and $result.Error) {
            Write-OpActivityLog -Message "${label}: ошибка — $($result.Error)"
            $err = [string]$result.Error
            $tip = 'OpenProject: Error'
            if ($err.Length -gt 0) {
                $short = $err
                if ($short.Length -gt 40) { $short = $short.Substring(0, 37) + '...' }
                $tip = "OpenProject: $short"
            }
            Set-TrayVisualState -State 'Error' -Tip $tip
            Show-Balloon 'OpenProject' ('Ошибка: ' + $err) 'Error'
        } else {
            switch ($ActionName) {
                'start' {
                    $mode = 'OK'
                    if ($result -and $result.Mode) { $mode = $result.Mode }
                    $script:LastErrorTip = $null
                    Write-OpActivityLog -Message "${label}: готово ($mode)"
                    Show-Balloon 'OpenProject' "Готово ($mode)."
                }
                'stop' {
                    $script:LastErrorTip = $null
                    Write-OpActivityLog -Message "${label}: готово"
                    Show-Balloon 'OpenProject' 'Остановлено'
                }
                'restart' {
                    $script:LastErrorTip = $null
                    Write-OpActivityLog -Message "${label}: готово"
                    Show-Balloon 'OpenProject' 'Перезапущено.'
                }
                'restart-migrate' {
                    $script:LastErrorTip = $null
                    Write-OpActivityLog -Message "${label}: готово"
                    Show-Balloon 'OpenProject' 'Migrate + перезапуск готовы.'
                }
                'doctor' {
                    $report = ''
                    $ok = $true
                    if ($result -and $result.Report) { $report = [string]$result.Report }
                    if ($result -and $result.ContainsKey('Ok')) { $ok = [bool]$result.Ok }
                    Write-OpActivityLog -Message ("${label}: " + $(if ($ok) { 'OK' } else { 'FAIL' }))
                    # Doctor is diagnostic only — do not paint Error badge on the tray icon.
                    if ($report) {
                        Show-ReportDialog -Title 'Проверка окружения' -PathHint 'Результат doctor (без внешних окон)' -Text $report
                    } else {
                        Show-Balloon 'OpenProject' $(if ($ok) { 'Проверка: OK' } else { 'Проверка: ошибка' }) $(if ($ok) { 'Info' } else { 'Warning' })
                    }
                }
                'pending-migrate' {
                    $n = 0
                    if ($result -and $result.ContainsKey('Pending')) { $n = [int]$result.Pending }
                    Write-OpActivityLog -Message "${label}: $n"
                    if ($n -gt 0) {
                        Show-Balloon 'OpenProject' "Pending migrations: $n. Можно «Перезапуск + migrate»." 'Warning'
                    } else {
                        Show-Balloon 'OpenProject' 'Pending migrations: 0'
                    }
                }
            }
        }
    } catch {
        Write-OpActivityLog -Message "${label}: ошибка — $($_.Exception.Message)"
        Set-TrayVisualState -State 'Error' -Tip 'OpenProject: Error'
        Show-Balloon 'OpenProject' ('Ошибка: ' + $_.Exception.Message) 'Error'
    } finally {
        try { $Ps.Dispose() } catch { }
        try { if ($Ps.Runspace) { $Ps.Runspace.Dispose() } } catch { }
        $script:Busy = $false
        $script:BusyStartedAt = $null
        # Always refresh from TCP so Error recovers when stack is up / Stop shows Stopped.
        Update-TrayStatus
    }
}

function Start-BackgroundOp {
    param(
        [Parameter(Mandatory)][ValidateSet('start', 'stop', 'restart', 'restart-migrate', 'doctor', 'pending-migrate')][string]$ActionName,
        [Parameter(Mandatory)][string]$BusyText
    )
    if ($script:Busy) {
        Show-Balloon 'OpenProject' 'Уже выполняется операция...' 'Warning'
        return
    }

    $label = Get-ActionLogLabel -ActionName $ActionName
    Write-OpActivityLog -Message "${label}: начато"

    $script:Busy = $true
    $script:BusyStartedAt = Get-Date
    if ($ActionName -in @('start', 'restart', 'restart-migrate')) {
        Set-TrayVisualState -State 'Starting' -Tip $BusyText
    } else {
        Set-TrayTip $BusyText
    }
    Set-MenuBusyState -Busy $true

    $trayDir = $script:TrayDir
    $openBrowser = [bool]$script:OpOpenBrowserOnStart
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($TrayDir, $ActionName, $OpenBrowser)
        $ErrorActionPreference = 'Stop'
        try {
            . (Join-Path $TrayDir 'OpenProject-Tray.Core.ps1')
            Initialize-OpenProjectTrayCore -TrayDir $TrayDir
            $browser = [bool]$OpenBrowser
            $out = $null
            switch ($ActionName) {
                'start' {
                    if ($browser) { $out = Start-OpenProjectPipeline -OpenBrowserWhenReady }
                    else { $out = Start-OpenProjectPipeline }
                }
                'stop' {
                    Stop-OpenProjectDevStack
                    Start-Sleep -Seconds 1
                    $out = @{ Mode = 'Stop'; Ready = $true }
                }
                'restart' {
                    if ($browser) { $out = Restart-OpenProjectPipeline -OpenBrowserWhenReady }
                    else { $out = Restart-OpenProjectPipeline }
                }
                'restart-migrate' {
                    if ($browser) { $out = Restart-OpenProjectPipeline -WithMigrate -OpenBrowserWhenReady }
                    else { $out = Restart-OpenProjectPipeline -WithMigrate }
                }
                'doctor' { $out = Invoke-OpDoctorCheck }
                'pending-migrate' { $out = Get-OpPendingMigrationCount }
            }
            # Prevent hashtable enumeration into DictionaryEntry / leaked ints in EndInvoke.
            Write-Output -NoEnumerate $out
        } catch {
            Write-Output -NoEnumerate @{ Error = $_.Exception.Message; Ready = $false }
        }
    }).AddArgument($trayDir).AddArgument($ActionName).AddArgument($openBrowser)

    $script:BgPowerShell = $ps
    $script:BgActionName = $ActionName
    $script:BgHandle = $ps.BeginInvoke()

    if (-not $script:PollTimer) {
        $script:PollTimer = New-Object System.Windows.Forms.Timer
        $script:PollTimer.Interval = 250
        $script:PollTimer.Add_Tick({
            if (-not $script:BgHandle) { $script:PollTimer.Stop(); return }
            if ($script:Busy -and $script:BusyStartedAt -and $script:BgActionName -in @('start', 'restart', 'restart-migrate', 'doctor', 'pending-migrate')) {
                $sec = [int]((Get-Date) - $script:BusyStartedAt).TotalSeconds
                $label = Get-ActionLogLabel -ActionName $script:BgActionName
                if ($script:BgActionName -in @('start', 'restart', 'restart-migrate')) {
                    Set-TrayVisualState -State 'Starting' -Tip ("OpenProject: Starting ${sec}s")
                } else {
                    Set-TrayTip ("OpenProject: $label ${sec}s")
                }
            }
            if ($script:BgHandle -and $script:BgHandle.IsCompleted) {
                # Claim completion BEFORE any modal UI. EndInvoke is idempotent in PS 5.1,
                # so a Tick during ShowDialog would otherwise open report windows forever.
                $psDone = $script:BgPowerShell
                $handleDone = $script:BgHandle
                $actionDone = $script:BgActionName
                $script:PollTimer.Stop()
                $script:BgPowerShell = $null
                $script:BgHandle = $null
                $script:BgActionName = $null
                Complete-BackgroundOp -Ps $psDone -Handle $handleDone -ActionName $actionDone
            }
        })
    }
    $script:PollTimer.Start()
}

function Invoke-UiStart {
    Show-Balloon 'OpenProject' 'Запуск в фоне (WSL + Postgres + bin/dev)...'
    Start-BackgroundOp -ActionName 'start' -BusyText 'OpenProject: Starting...'
}

function Invoke-UiStop {
    Show-Balloon 'OpenProject' 'Остановка в фоне...'
    Start-BackgroundOp -ActionName 'stop' -BusyText 'OpenProject: stop...'
}

function Invoke-UiRestart {
    Show-Balloon 'OpenProject' 'Перезапуск в фоне...'
    Start-BackgroundOp -ActionName 'restart' -BusyText 'OpenProject: Starting...'
}

function Invoke-UiRestartMigrate {
    Show-Balloon 'OpenProject' 'Migrate + перезапуск (bundle install, db:migrate)...'
    Start-BackgroundOp -ActionName 'restart-migrate' -BusyText 'OpenProject: migrate...'
}

function Invoke-UiDoctor {
    # No balloon here — keeps focus quiet; progress is tip-only.
    Start-BackgroundOp -ActionName 'doctor' -BusyText 'OpenProject: doctor...'
}

function Invoke-UiPendingMigrate {
    Show-Balloon 'OpenProject' 'Проверка pending migrations...'
    Start-BackgroundOp -ActionName 'pending-migrate' -BusyText 'OpenProject: pending...'
}

function Show-SettingsDialog {
    $current = Read-OpSettings -TrayDir $script:TrayDir
    $shell = New-OpDialogShell -Title 'Настройки' -Subtitle 'OpenProject Tray' -Width 520 -Height 520 -Fixed
    $form = $shell.Form
    $footer = $shell.Footer
    $t = $shell.Theme

    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.AutoScroll = $true
    $body.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 8)
    $body.BackColor = $t.Surface
    $form.Controls.Add($body)
    $body.BringToFront()

    $script:SettingsFields = @{}
    $y = 8
    $fieldDefs = @(
        @{ Key = 'OpenProjectRoot'; Caption = 'Путь OpenProject (Linux)'; Value = $current.OpenProjectRoot },
        @{ Key = 'Distro'; Caption = 'WSL distro'; Value = $current.Distro },
        @{ Key = 'LinuxUser'; Caption = 'Linux user'; Value = $current.LinuxUser },
        @{ Key = 'Url'; Caption = 'URL'; Value = $current.Url },
        @{ Key = 'ColdReadyTimeoutSec'; Caption = 'Cold timeout (сек)'; Value = $current.ColdReadyTimeoutSec },
        @{ Key = 'WarmReadyTimeoutSec'; Caption = 'Warm timeout (сек)'; Value = $current.WarmReadyTimeoutSec },
        @{ Key = 'PrepareTimeoutSec'; Caption = 'Migrate timeout (сек)'; Value = $current.PrepareTimeoutSec }
    )
    foreach ($def in $fieldDefs) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $def.Caption
        $lbl.ForeColor = $t.Muted
        $lbl.Location = New-Object System.Drawing.Point(4, $y)
        $lbl.AutoSize = $true
        $body.Controls.Add($lbl)
        $y += 20
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(4, $y)
        $tb.Width = 460
        $tb.Height = 28
        $tb.BorderStyle = 'FixedSingle'
        $tb.Text = [string]$def.Value
        $body.Controls.Add($tb)
        $script:SettingsFields[$def.Key] = $tb
        $y += 36
    }

    $script:SettingsChkWin = New-Object System.Windows.Forms.CheckBox
    $script:SettingsChkWin.Text = 'Автозапуск трея с Windows'
    $script:SettingsChkWin.AutoSize = $true
    $script:SettingsChkWin.Location = New-Object System.Drawing.Point(4, $y)
    $script:SettingsChkWin.Checked = (Test-OpWindowsStartup)
    $body.Controls.Add($script:SettingsChkWin)
    $y += 28

    $script:SettingsChkAuto = New-Object System.Windows.Forms.CheckBox
    $script:SettingsChkAuto.Text = 'Автозапуск OpenProject при старте трея'
    $script:SettingsChkAuto.AutoSize = $true
    $script:SettingsChkAuto.Location = New-Object System.Drawing.Point(4, $y)
    $script:SettingsChkAuto.Checked = [bool]$current.AutoStartOpenProject
    $body.Controls.Add($script:SettingsChkAuto)
    $y += 28

    $script:SettingsChkBrowser = New-Object System.Windows.Forms.CheckBox
    $script:SettingsChkBrowser.Text = 'Открывать браузер после старта / перезапуска'
    $script:SettingsChkBrowser.AutoSize = $true
    $script:SettingsChkBrowser.Location = New-Object System.Drawing.Point(4, $y)
    $script:SettingsChkBrowser.Checked = [bool]$current.OpenBrowserOnStart
    $body.Controls.Add($script:SettingsChkBrowser)

    $script:SettingsForm = $form
    $script:SettingsBase = $current

    $btnCancel = New-OpDialogButton -Text 'Отмена'
    $btnCancel.Anchor = 'Top,Right'
    $btnCancel.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 228), 12)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $footer.Controls.Add($btnCancel)

    $btnOk = New-OpDialogButton -Text 'Сохранить' -Primary -Width 110
    $btnOk.Anchor = 'Top,Right'
    $btnOk.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 120), 12)
    $footer.Controls.Add($btnOk)
    $form.CancelButton = $btnCancel
    $form.AcceptButton = $btnOk
    $footer.Add_Resize({
        $btnCancel.Left = $footer.ClientSize.Width - 228
        $btnOk.Left = $footer.ClientSize.Width - 120
    })

    $btnOk.Add_Click({
        try {
            $next = Merge-OpSettingsDefaults -Raw (ConvertTo-OpSettingsHashtable $script:SettingsBase)
            foreach ($k in @('OpenProjectRoot', 'Distro', 'LinuxUser', 'Url')) {
                $next[$k] = $script:SettingsFields[$k].Text.Trim()
            }
            foreach ($k in @('ColdReadyTimeoutSec', 'WarmReadyTimeoutSec', 'PrepareTimeoutSec')) {
                $next[$k] = [int]$script:SettingsFields[$k].Text.Trim()
            }
            $next['StartWithWindows'] = [bool]$script:SettingsChkWin.Checked
            $next['AutoStartOpenProject'] = [bool]$script:SettingsChkAuto.Checked
            $next['OpenBrowserOnStart'] = [bool]$script:SettingsChkBrowser.Checked
            Assert-OpSettingsValid -Settings $next
            Set-OpWindowsStartup -TrayDir $script:TrayDir -Enabled ([bool]$script:SettingsChkWin.Checked)
            $saved = Write-OpSettings -TrayDir $script:TrayDir -Settings $next
            Initialize-OpenProjectTrayCore -TrayDir $script:TrayDir -Settings $saved
            Write-OpActivityLog -Message 'Настройки сохранены'
            $script:SettingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $script:SettingsForm.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'Настройки',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    [void]$form.ShowDialog($script:HiddenForm)
    $form.Dispose()
    $script:SettingsForm = $null
    $script:SettingsFields = $null
}

function Show-ActivityLogDialog {
    $logPath = Get-OpActivityLogPath -TrayDir $script:TrayDir
    $shell = New-OpDialogShell -Title 'Журнал трея' -Subtitle $logPath -Width 780 -Height 580
    $form = $shell.Form
    $footer = $shell.Footer
    $t = $shell.Theme

    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 8)
    $body.BackColor = $t.Surface
    $form.Controls.Add($body)
    $body.BringToFront()

    $card = New-OpRoundedCard -BackColor $t.LogBg
    $card.Dock = 'Fill'
    $body.Controls.Add($card)

    $tb = New-OpLogTextBox
    $card.Controls.Add($tb)
    $script:LogViewBox = $tb
    $form.Tag = $tb

    $loadLog = {
        $box = $script:LogViewBox
        if (-not $box) { return }
        $box.Text = Read-OpActivityLogText -TrayDir $script:TrayDir
        Set-OpLogViewerToEnd -Box $box
    }

    $btnRefresh = New-OpDialogButton -Text 'Обновить' -Width 100
    $btnRefresh.Location = New-Object System.Drawing.Point(16, 12)
    $footer.Controls.Add($btnRefresh)
    $btnRefresh.Add_Click($loadLog)

    $btnNotepad = New-OpDialogButton -Text 'В блокноте' -Width 110
    $btnNotepad.Location = New-Object System.Drawing.Point(126, 12)
    $footer.Controls.Add($btnNotepad)
    $btnNotepad.Add_Click({
        try {
            $p = Get-OpActivityLogPath -TrayDir $script:TrayDir
            $dir = Split-Path -Parent $p
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            if (-not (Test-Path -LiteralPath $p)) {
                [System.IO.File]::WriteAllText($p, '', [System.Text.UTF8Encoding]::new($false))
            }
            Start-Process notepad.exe -ArgumentList $p
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Журнал') | Out-Null
        }
    })

    $btnClose = New-OpDialogButton -Text 'Закрыть' -Primary
    $btnClose.Anchor = 'Top,Right'
    $btnClose.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 120), 12)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $footer.Controls.Add($btnClose)
    $form.CancelButton = $btnClose
    $footer.Add_Resize({
        $btnClose.Left = $footer.ClientSize.Width - 120
    })

    $form.Add_Shown({
        if ($script:LogViewBox) {
            $script:LogViewBox.Text = Read-OpActivityLogText -TrayDir $script:TrayDir
            Set-OpLogViewerToEnd -Box $script:LogViewBox
            $script:LogViewBox.Focus()
        }
    })

    [void]$form.ShowDialog($script:HiddenForm)
    $form.Dispose()
    $script:LogViewBox = $null
}

function Show-WslLogTailDialog {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$LinuxPath
    )
    try {
        $text = Read-OpWslTextFile -LinuxPath $LinuxPath -TailLines 250
        Show-ReportDialog -Title $Title -PathHint $LinuxPath -Text $text
    } catch {
        Show-Balloon 'OpenProject' ('Лог: ' + $_.Exception.Message) 'Error'
    }
}

function Stop-TrayApplication {
    if ($script:DesktopTimer) { $script:DesktopTimer.Stop(); $script:DesktopTimer.Dispose() }
    if ($script:DesktopBridge) { $script:DesktopBridge.Dispose(); $script:DesktopBridge = $null }
    Write-OpActivityLog -Message 'Трей: выход'
    try {
        if ($script:Timer) { $script:Timer.Stop(); $script:Timer.Dispose() }
    } catch { }
    try {
        if ($script:PollTimer) { $script:PollTimer.Stop(); $script:PollTimer.Dispose() }
    } catch { }
    try {
        if ($script:BgPowerShell) {
            try { $script:BgPowerShell.Stop() } catch { }
            try { $script:BgPowerShell.Dispose() } catch { }
            try {
                if ($script:BgPowerShell.Runspace) { $script:BgPowerShell.Runspace.Dispose() }
            } catch { }
        }
    } catch { }
    try {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
    } catch { }
    try { Dispose-TrayIcons } catch { }
    try {
        if ($script:InstanceMutex) {
            $script:InstanceMutex.ReleaseMutex()
            $script:InstanceMutex.Dispose()
        }
    } catch { }
    $script:HiddenForm.Close()
}

# Single-instance guard (avoid duplicate tray icons)
$script:InstanceMutex = New-Object System.Threading.Mutex($false, 'Local\OpenProjectTray.Singleton')
if (-not $script:InstanceMutex.WaitOne(0, $false)) {
    if (-not $Background -and -not $Startup) { try { [OpenProjectTray.BridgeClient]::Request('activate') | Out-Null } catch { } }
    exit 0
}

# Hidden form provides message pump + keeps tray alive
$script:HiddenForm = New-Object System.Windows.Forms.Form
$script:HiddenForm.FormBorderStyle = 'FixedToolWindow'
$script:HiddenForm.ShowInTaskbar = $false
$script:HiddenForm.WindowState = 'Minimized'
$script:HiddenForm.Opacity = 0
$script:HiddenForm.Size = New-Object System.Drawing.Size(1, 1)

Initialize-TrayIcons
$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.Icon = $script:StatusIcons['Stopped']
$script:NotifyIcon.Visible = $true
Set-TrayVisualState -State 'Stopped'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Font = (Get-OpUiTheme).FontUi
$menu.BackColor = (Get-OpUiTheme).MenuBg
$menu.ForeColor = (Get-OpUiTheme).Text
$menu.ShowImageMargin = $true
$menu.ShowCheckMargin = $false
$menu.Padding = New-Object System.Windows.Forms.Padding(6, 8, 6, 8)
$menu.Renderer = New-Object OpTray.UiMenuRenderer
$menu.Add_Opening({
    Update-OpRoundedRegion -Control $menu -Radius ((Get-OpUiTheme).RadiusMenu)
})
$menu.Add_SizeChanged({
    if ($menu.Visible) {
        Update-OpRoundedRegion -Control $menu -Radius ((Get-OpUiTheme).RadiusMenu)
    }
})

$script:MenuStatusItem = New-Object System.Windows.Forms.ToolStripMenuItem (Get-OpStateCaption -State 'Stopped')
$script:MenuStatusItem.Enabled = $false
$script:MenuStatusItem.ForeColor = Get-OpStateColor -State 'Stopped'
$script:MenuStatusItem.ImageScaling = [System.Windows.Forms.ToolStripItemImageScaling]::None
if ($script:StatusMenuImages['Stopped']) {
    $script:MenuStatusItem.Image = $script:StatusMenuImages['Stopped']
}

$script:MenuStart = New-Object System.Windows.Forms.ToolStripMenuItem 'Старт'
$script:MenuRestart = New-Object System.Windows.Forms.ToolStripMenuItem 'Перезапуск'
$script:MenuRestartMigrate = New-Object System.Windows.Forms.ToolStripMenuItem 'Перезапуск + migrate'
$script:MenuStop = New-Object System.Windows.Forms.ToolStripMenuItem 'Стоп'
$script:MenuBrowser = New-Object System.Windows.Forms.ToolStripMenuItem 'Открыть в браузере'
$script:MenuTerminal = New-Object System.Windows.Forms.ToolStripMenuItem 'Терминал в проекте'
$script:MenuDoctor = New-Object System.Windows.Forms.ToolStripMenuItem 'Проверка окружения'
$script:MenuPending = New-Object System.Windows.Forms.ToolStripMenuItem 'Pending migrations?'
$script:MenuLogs = New-Object System.Windows.Forms.ToolStripMenuItem 'Логи'
$script:MenuSettings = New-Object System.Windows.Forms.ToolStripMenuItem 'Настройки…'
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem 'Выход'

$menuLogActivity = New-Object System.Windows.Forms.ToolStripMenuItem 'Журнал трея…'
$menuLogDev = New-Object System.Windows.Forms.ToolStripMenuItem 'tray-dev.log — хвост'
$menuLogDevNotepad = New-Object System.Windows.Forms.ToolStripMenuItem 'tray-dev.log — блокнот'
$menuLogDevFollow = New-Object System.Windows.Forms.ToolStripMenuItem 'Следить tray-dev.log'
$menuLogPrep = New-Object System.Windows.Forms.ToolStripMenuItem 'tray-prepare.log — хвост'
$menuLogPrepNotepad = New-Object System.Windows.Forms.ToolStripMenuItem 'tray-prepare.log — блокнот'
$script:MenuLogs.DropDown.Font = (Get-OpUiTheme).FontUi
$script:MenuLogs.DropDown.BackColor = (Get-OpUiTheme).MenuBg
$script:MenuLogs.DropDown.ForeColor = (Get-OpUiTheme).Text
$script:MenuLogs.DropDown.Padding = New-Object System.Windows.Forms.Padding(6, 8, 6, 8)
$script:MenuLogs.DropDown.Renderer = New-Object OpTray.UiMenuRenderer
$script:MenuLogs.DropDown.Add_Opening({
    Update-OpRoundedRegion -Control $script:MenuLogs.DropDown -Radius ((Get-OpUiTheme).RadiusMenu)
})
$script:MenuLogs.DropDown.Add_SizeChanged({
    if ($script:MenuLogs.DropDown.Visible) {
        Update-OpRoundedRegion -Control $script:MenuLogs.DropDown -Radius ((Get-OpUiTheme).RadiusMenu)
    }
})
[void]$script:MenuLogs.DropDownItems.Add($menuLogActivity)
[void]$script:MenuLogs.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:MenuLogs.DropDownItems.Add($menuLogDev)
[void]$script:MenuLogs.DropDownItems.Add($menuLogDevNotepad)
[void]$script:MenuLogs.DropDownItems.Add($menuLogDevFollow)
[void]$script:MenuLogs.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:MenuLogs.DropDownItems.Add($menuLogPrep)
[void]$script:MenuLogs.DropDownItems.Add($menuLogPrepNotepad)

[void]$menu.Items.Add($script:MenuStatusItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:MenuStart)
[void]$menu.Items.Add($script:MenuRestart)
[void]$menu.Items.Add($script:MenuRestartMigrate)
[void]$menu.Items.Add($script:MenuStop)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:MenuBrowser)
[void]$menu.Items.Add($script:MenuTerminal)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:MenuDoctor)
[void]$menu.Items.Add($script:MenuPending)
[void]$menu.Items.Add($script:MenuLogs)
[void]$menu.Items.Add($script:MenuSettings)
$pluginMenu = New-Object System.Windows.Forms.ToolStripMenuItem 'Плагин StreamDock…'
$pluginMenu.Add_Click({ Show-OpPluginDialog })
[void]$menu.Items.Add($pluginMenu)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($menuExit)
$script:NotifyIcon.ContextMenuStrip = $menu

$script:MenuStart.Add_Click({ Invoke-UiStart })
$script:MenuStop.Add_Click({ Invoke-UiStop })
$script:MenuRestart.Add_Click({ Invoke-UiRestart })
$script:MenuRestartMigrate.Add_Click({ Invoke-UiRestartMigrate })
$script:MenuDoctor.Add_Click({ Invoke-UiDoctor })
$script:MenuPending.Add_Click({ Invoke-UiPendingMigrate })
$script:MenuTerminal.Add_Click({
    try {
        Open-OpProjectTerminal
        Write-OpActivityLog -Message 'Терминал: открыт'
    } catch {
        Show-Balloon 'OpenProject' ('Терминал: ' + $_.Exception.Message) 'Error'
    }
})
$menuLogActivity.Add_Click({
    try { Show-ActivityLogDialog } catch {
        Show-Balloon 'OpenProject' ('Журнал: ' + $_.Exception.Message) 'Error'
    }
})
$menuLogDev.Add_Click({
    Show-WslLogTailDialog -Title 'tray-dev.log' -LinuxPath (Get-OpDevLogHint)
})
$menuLogDevNotepad.Add_Click({
    try {
        Open-OpWslLogInNotepad -LinuxPath (Get-OpDevLogHint)
    } catch {
        Show-Balloon 'OpenProject' ('Лог: ' + $_.Exception.Message) 'Error'
    }
})
$menuLogDevFollow.Add_Click({
    try {
        Start-OpWslLogFollow -LinuxPath (Get-OpDevLogHint)
        Write-OpActivityLog -Message 'Лог: follow tray-dev.log'
    } catch {
        Show-Balloon 'OpenProject' ('Follow: ' + $_.Exception.Message) 'Error'
    }
})
$menuLogPrep.Add_Click({
    Show-WslLogTailDialog -Title 'tray-prepare.log' -LinuxPath (Get-OpPrepareLogHint)
})
$menuLogPrepNotepad.Add_Click({
    try {
        Open-OpWslLogInNotepad -LinuxPath (Get-OpPrepareLogHint)
    } catch {
        Show-Balloon 'OpenProject' ('Лог: ' + $_.Exception.Message) 'Error'
    }
})
$script:MenuSettings.Add_Click({
    try { Show-SettingsDialog } catch {
        Show-Balloon 'OpenProject' ('Настройки: ' + $_.Exception.Message) 'Error'
    }
})
$script:MenuBrowser.Add_Click({
    try { Open-OpenProjectBrowser } catch {
        Show-Balloon 'OpenProject' ('Браузер: ' + $_.Exception.Message) 'Error'
    }
})
$script:NotifyIcon.Add_DoubleClick({
    try { Open-OpenProjectBrowser } catch { }
})

$menuExit.Add_Click({ Stop-TrayApplication })

$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 5000
$script:Timer.Add_Tick({ Update-TrayStatus })
$script:Timer.Start()

Update-TrayStatus
Start-OpDesktopBridge
Write-OpActivityLog -Message 'Трей: готов'

if ((-not $Background) -or ($Startup -and $script:OpAutoStartOpenProject)) {
    $script:AutoStartTimer = New-Object System.Windows.Forms.Timer
    $script:AutoStartTimer.Interval = 300
    $script:AutoStartTimer.Add_Tick({
        $script:AutoStartTimer.Stop()
        $script:AutoStartTimer.Dispose()
        if ($Startup) { if (-not (Test-OpenProjectQuick)) { Invoke-UiStart } }
        else { Invoke-OpActivate }
    })
    $script:AutoStartTimer.Start()
}

[System.Windows.Forms.Application]::Run($script:HiddenForm)
