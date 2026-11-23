#requires -Version 5.1
<#
.SYNOPSIS
    Windows ToDo Popup - nhắc việc Microsoft To Do mỗi buổi sáng bằng popup gọn nhẹ.

.DESCRIPTION
    Chạy 1 lần (do Task Scheduler gọi), lấy các task chưa hoàn thành có hạn hôm nay
    hoặc đã quá hạn từ Microsoft To Do (qua Microsoft Graph), hiện popup rồi thoát.
    Không có tiến trình nào chạy ngầm liên tục.

    LƯU Ý: file này PHẢI lưu dạng "UTF-8 with BOM" để Windows PowerShell 5.1 đọc đúng
    tiếng Việt. Repo có CI kiểm tra điều này.

.PARAMETER Force
    Chạy ngay: bỏ qua khung giờ và giới hạn "mỗi ngày 1 lần", luôn hiện popup
    (kể cả khi không có việc nào). Dùng cho shortcut "Chạy ngay".

.PARAMETER Login
    Chỉ đăng nhập Microsoft (dùng khi cần đăng nhập lại).

.PARAMETER Demo
    Hiện popup với dữ liệu mẫu, không cần đăng nhập. Dùng để xem thử / chụp ảnh README.

.PARAMETER Snoozed
    Dùng nội bộ: lần chạy do nút "Nhắc lại sau..." đặt lịch.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Login,
    [switch]$Demo,
    [switch]$Snoozed
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# =====================================================================
# HẰNG SỐ
# =====================================================================
$AppName     = 'WindowsTodoPopup'
$GraphScopes = @('Tasks.ReadWrite')
$WindowTitle = 'Nhắc việc buổi sáng'
$DataDir     = Join-Path $env:LOCALAPPDATA $AppName
$LogPath     = Join-Path $DataDir 'debug.log'
$StampPath   = Join-Path $DataDir 'last_shown.txt'
$ConfigPath  = Join-Path $PSScriptRoot 'config.json'

if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

# =====================================================================
# TIỆN ÍCH CHUNG
# =====================================================================
function Write-Log {
    param([string]$Message)
    try {
        if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 262144)) {
            Remove-Item -LiteralPath $LogPath -Force
        }
        $line = '{0} {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText($LogPath, $line, [System.Text.Encoding]::UTF8)
    } catch {
        # Ghi log thất bại thì bỏ qua, không để làm hỏng chương trình.
    }
}

function Show-Message {
    param(
        [string]$Text,
        [string]$Icon = 'Information',
        [string]$Buttons = 'OK'
    )
    return [System.Windows.Forms.MessageBox]::Show($Text, $WindowTitle, $Buttons, $Icon)
}

function ConvertTo-Color {
    param([string]$Html, [string]$Fallback)
    try {
        return [System.Drawing.ColorTranslator]::FromHtml($Html)
    } catch {
        return [System.Drawing.ColorTranslator]::FromHtml($Fallback)
    }
}

function Get-AppConfig {
    $cfg = [ordered]@{
        RunUntilHour  = 12
        ShowOverdue   = $true
        ExcludeLists  = @()
        SnoozeMinutes = 60
        AccentColor   = '#0078D4'
        OverdueColor  = '#C45A4E'
        InkColor      = '#111114'
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw  = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
            $json = $raw | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) {
                if ($cfg.Contains($prop.Name)) { $cfg[$prop.Name] = $prop.Value }
            }
        } catch {
            Write-Log ('config.json lỗi, dùng mặc định: ' + $_.Exception.Message)
        }
    }

    $hour = 12
    if (-not [int]::TryParse([string]$cfg['RunUntilHour'], [ref]$hour)) { $hour = 12 }
    $cfg['RunUntilHour'] = [Math]::Min(24, [Math]::Max(0, $hour))

    $snooze = 60
    if (-not [int]::TryParse([string]$cfg['SnoozeMinutes'], [ref]$snooze)) { $snooze = 60 }
    $cfg['SnoozeMinutes'] = [Math]::Min(720, [Math]::Max(1, $snooze))

    $cfg['ShowOverdue']  = [bool]$cfg['ShowOverdue']
    $cfg['ExcludeLists'] = @($cfg['ExcludeLists'] | Where-Object { $_ })
    return $cfg
}

function Test-ShownToday {
    try {
        if (Test-Path -LiteralPath $StampPath) {
            $saved = [System.IO.File]::ReadAllText($StampPath).Trim()
            return ($saved -eq (Get-Date).ToString('yyyy-MM-dd'))
        }
    } catch { }
    return $false
}

function Set-ShownToday {
    try {
        [System.IO.File]::WriteAllText($StampPath, (Get-Date).ToString('yyyy-MM-dd'))
    } catch {
        Write-Log ('Không ghi được last_shown.txt: ' + $_.Exception.Message)
    }
}

# =====================================================================
# MICROSOFT GRAPH
# =====================================================================
function Wait-ForNetwork {
    param([int]$Attempts = 8, [int]$DelaySeconds = 10)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            [void][System.Net.Dns]::GetHostAddresses('graph.microsoft.com')
            return $true
        } catch {
            if ($i -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
        }
    }
    return $false
}

function Connect-TodoGraph {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    # Đã đăng nhập trước đó -> dùng lại token lưu sẵn (không hỏi lại).
    # Token hết hạn -> trình duyệt tự mở để đăng nhập lại.
    Connect-MgGraph -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
    Write-Log 'Đã kết nối Microsoft Graph.'
}

function Invoke-GraphPaged {
    param([string]$Uri)
    $items = New-Object System.Collections.ArrayList
    while ($Uri) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        foreach ($v in $resp.value) { [void]$items.Add($v) }
        $Uri = $resp.'@odata.nextLink'
    }
    return $items.ToArray()
}

# Quy đổi hạn (due date) của Graph (UTC hoặc timezone ghi trong field) sang NGÀY theo giờ địa phương.
function Convert-GraphDueDate {
    param($DueDateTime)
    if (-not $DueDateTime -or -not $DueDateTime.dateTime) { return $null }

    $raw  = [datetime]::Parse($DueDateTime.dateTime, [System.Globalization.CultureInfo]::InvariantCulture)
    $tzId = $DueDateTime.timeZone

    try {
        if ($tzId -eq 'UTC') {
            $utc = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Utc)
        } else {
            $tz          = [System.TimeZoneInfo]::FindSystemTimeZoneById($tzId)
            $unspecified = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Unspecified)
            $utc         = [System.TimeZoneInfo]::ConvertTimeToUtc($unspecified, $tz)
        }
    } catch {
        $utc = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Utc)
    }
    return $utc.ToLocalTime().Date
}

function Get-TodoTasks {
    param($Config)

    $todayDate  = (Get-Date).Date
    $found      = New-Object System.Collections.ArrayList
    $errorCount = 0

    $lists = @(Invoke-GraphPaged -Uri 'https://graph.microsoft.com/v1.0/me/todo/lists')
    Write-Log ('Số list lấy được: ' + $lists.Count)

    $filter = [uri]::EscapeDataString("status ne 'completed'")

    foreach ($list in $lists) {
        if ($Config.ExcludeLists -contains $list.displayName) { continue }

        $uri = 'https://graph.microsoft.com/v1.0/me/todo/lists/' + $list.id + '/tasks?$filter=' + $filter + '&$top=100'
        try {
            foreach ($t in @(Invoke-GraphPaged -Uri $uri)) {
                $due = Convert-GraphDueDate $t.dueDateTime
                if (-not $due) { continue }          # không có hạn -> bỏ qua
                if ($due -gt $todayDate) { continue } # hạn trong tương lai -> bỏ qua

                $isOverdue = ($due -lt $todayDate)
                if ($isOverdue -and -not $Config.ShowOverdue) { continue }

                [void]$found.Add([pscustomobject]@{
                    Id         = [string]$t.id
                    ListId     = [string]$list.id
                    Title      = [string]$t.title
                    DueDate    = $due
                    IsOverdue  = $isOverdue
                    Importance = [string]$t.importance
                })
            }
        } catch {
            $errorCount++
            Write-Log ("Lỗi khi lấy task của list '" + $list.displayName + "': " + $_.Exception.Message)
        }
    }

    # Hôm nay trước, quá hạn sau (cũ nhất lên đầu). Bọc @() để tránh lỗi $null khi mảng rỗng.
    $sorted = @($found | Sort-Object IsOverdue, DueDate, Title)
    Write-Log ('Tổng task hợp lệ: ' + $sorted.Count)
    return [pscustomobject]@{ Tasks = $sorted; ErrorCount = $errorCount }
}

function Set-TodoTaskStatus {
    param([string]$ListId, [string]$TaskId, [string]$Status)
    $body = @{ status = $Status } | ConvertTo-Json -Compress
    $uri  = 'https://graph.microsoft.com/v1.0/me/todo/lists/' + $ListId + '/tasks/' + $TaskId
    Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
}

function Get-DemoTasks {
    $today = (Get-Date).Date
    return @(
        [pscustomobject]@{ Id = 'demo1'; ListId = 'demo'; Title = 'Gửi báo giá cho khách hàng'; DueDate = $today; IsOverdue = $false; Importance = 'high' }
        [pscustomobject]@{ Id = 'demo2'; ListId = 'demo'; Title = 'Mua sữa và trứng trên đường về'; DueDate = $today; IsOverdue = $false; Importance = 'normal' }
        [pscustomobject]@{ Id = 'demo3'; ListId = 'demo'; Title = 'Đóng tiền internet tháng này (nhớ chụp lại hóa đơn)'; DueDate = $today.AddDays(-2); IsOverdue = $true; Importance = 'normal' }
    )
}

# =====================================================================
# NHẮC LẠI SAU (SNOOZE) - đặt lịch chạy 1 lần qua Task Scheduler
# =====================================================================
function Register-Snooze {
    param([int]$Minutes)
    $taskName  = $AppName + '-Snooze'
    $argument  = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Snoozed' -f $PSCommandPath
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($Minutes)
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12)
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Nhắc lại việc sau khi bấm Nhắc lại (tự xóa sau khi chạy)' -Force | Out-Null
    Write-Log ('Đã đặt nhắc lại sau ' + $Minutes + ' phút.')
}

# =====================================================================
# GIAO DIỆN POPUP - phong cách "Negative Space Design"
# (nền trắng, nhiều khoảng trắng, con số lớn làm điểm nhấn, 1 màu accent)
# =====================================================================
function Set-RoundedRegion {
    param($Control, [int]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $w = $Control.Width
    $h = $Control.Height
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc(($w - $d), 0, $d, $d, 270, 90)
    $path.AddArc(($w - $d), ($h - $d), $d, $d, 0, 90)
    $path.AddArc(0, ($h - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    $Control.Region = New-Object System.Drawing.Region($path)
}

function New-RowFont {
    param([bool]$Bold, [bool]$Strike)
    $style = [System.Drawing.FontStyle]::Regular
    if ($Bold)   { $style = $style -bor [System.Drawing.FontStyle]::Bold }
    if ($Strike) { $style = $style -bor [System.Drawing.FontStyle]::Strikeout }
    return New-Object System.Drawing.Font('Segoe UI', 10.5, $style)
}

function Update-Header {
    $script:lblBig.Text = [string]$script:remaining
    if ($script:remaining -gt 0) {
        $script:lblSub.Text = 'việc chưa hoàn thành'
    } elseif ($script:initialCount -eq 0) {
        $script:lblSub.Text = 'không có việc nào đến hạn'
    } else {
        $script:lblSub.Text = 'đã xong hết rồi'
    }
    $script:lblSnooze.Visible = ($script:remaining -gt 0)
}

function Invoke-TickTask {
    param($Chk)
    if ($script:tickBusy) { return }

    $info     = $Chk.Tag
    $wantDone = [bool]$Chk.Checked
    $status   = 'notStarted'
    if ($wantDone) { $status = 'completed' }

    $script:tickBusy = $true
    try {
        if (-not $info.IsDemo) {
            $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Set-TodoTaskStatus -ListId $info.ListId -TaskId $info.TaskId -Status $status
        }
        $info.Label.Font = New-RowFont $info.Bold $wantDone
        if ($wantDone) {
            $info.Label.ForeColor = $script:colorGray
            $script:remaining = $script:remaining - 1
        } else {
            $info.Label.ForeColor = $script:colorInk
            $script:remaining = $script:remaining + 1
        }
        Update-Header
    } catch {
        Write-Log ('Không cập nhật được task: ' + $_.Exception.Message)
        $Chk.Checked = (-not $wantDone)   # hoàn tác ô tick (handler bị chặn bởi tickBusy)
        [void](Show-Message "Không cập nhật được việc này trên Microsoft To Do.`nHãy kiểm tra kết nối mạng rồi thử lại." 'Warning')
    } finally {
        $script:form.Cursor = [System.Windows.Forms.Cursors]::Default
        $script:tickBusy = $false
    }
}

function Add-SectionHeader {
    param([string]$Text, $Color)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text        = $Text
    $lbl.Font        = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $lbl.ForeColor   = $Color
    $lbl.BackColor   = [System.Drawing.Color]::Transparent
    $lbl.UseMnemonic = $false
    $lbl.AutoSize    = $false
    $lbl.Size        = New-Object System.Drawing.Size(300, 18)
    $lbl.Location    = New-Object System.Drawing.Point(0, $script:rowY)
    $script:listPanel.Controls.Add($lbl)
    $script:rowY += 24
}

function Add-TaskRow {
    param($Task, [bool]$IsDemo)

    $isHigh    = ($Task.Importance -eq 'high')
    $font      = New-RowFont $isHigh $false
    $textWidth = 306
    $flags     = [System.Windows.Forms.TextFormatFlags]::WordBreak
    $measured  = [System.Windows.Forms.TextRenderer]::MeasureText($Task.Title, $font, (New-Object System.Drawing.Size($textWidth, 1000)), $flags)
    $textH     = [Math]::Max(20, $measured.Height + 2)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Size      = New-Object System.Drawing.Size(22, 22)
    $chk.Location  = New-Object System.Drawing.Point(0, ($script:rowY - 1))
    $chk.BackColor = [System.Drawing.Color]::Transparent
    $chk.Cursor    = [System.Windows.Forms.Cursors]::Hand

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text        = $Task.Title
    $lbl.Font        = $font
    $lbl.ForeColor   = $script:colorInk
    $lbl.BackColor   = [System.Drawing.Color]::Transparent
    $lbl.UseMnemonic = $false   # tiêu đề có ký tự & vẫn hiển thị đúng
    $lbl.AutoSize    = $false
    $lbl.Size        = New-Object System.Drawing.Size($textWidth, $textH)
    $lbl.Location    = New-Object System.Drawing.Point(32, $script:rowY)

    $chk.Tag = @{
        ListId = $Task.ListId
        TaskId = $Task.Id
        Label  = $lbl
        Bold   = $isHigh
        IsDemo = $IsDemo
    }
    $chk.Add_CheckedChanged({ param($s, $e) Invoke-TickTask $s })

    $script:listPanel.Controls.Add($chk)
    $script:listPanel.Controls.Add($lbl)
    $script:rowY += $textH

    if ($Task.IsOverdue) {
        $due = New-Object System.Windows.Forms.Label
        $due.Text        = 'Quá hạn từ ' + $Task.DueDate.ToString('dd/MM/yyyy')
        $due.Font        = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $due.ForeColor   = $script:colorOverdue
        $due.BackColor   = [System.Drawing.Color]::Transparent
        $due.UseMnemonic = $false
        $due.AutoSize    = $false
        $due.Size        = New-Object System.Drawing.Size($textWidth, 16)
        $due.Location    = New-Object System.Drawing.Point(32, ($script:rowY + 1))
        $script:listPanel.Controls.Add($due)
        $script:rowY += 18
    }
    $script:rowY += 12
}

function Show-TodoPopup {
    param([object[]]$Tasks, $Config, [bool]$IsDemo)

    $script:colorBg      = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $script:colorInk     = ConvertTo-Color $Config.InkColor '#111114'
    $script:colorGray    = [System.Drawing.Color]::FromArgb(140, 140, 148)
    $script:colorDivider = [System.Drawing.Color]::FromArgb(232, 232, 236)
    $script:colorAccent  = ConvertTo-Color $Config.AccentColor '#0078D4'
    $script:colorOverdue = ConvertTo-Color $Config.OverdueColor '#C45A4E'

    $script:remaining    = $Tasks.Count
    $script:initialCount = $Tasks.Count
    $script:tickBusy     = $false
    $script:isDemo       = $IsDemo
    $script:snoozeMin    = [int]$Config.SnoozeMinutes
    $script:rowY         = 0

    $formW = 420
    $formH = 490

    $script:form = New-Object System.Windows.Forms.Form
    $script:form.Text            = $WindowTitle
    $script:form.Size            = New-Object System.Drawing.Size($formW, $formH)
    $script:form.StartPosition   = 'CenterScreen'
    $script:form.FormBorderStyle = 'None'
    $script:form.TopMost         = $true
    $script:form.KeyPreview      = $true
    $script:form.BackColor       = $script:colorBg
    Set-RoundedRegion -Control $script:form -Radius 10

    # Viền mỏng để tách nền trắng khỏi desktop
    $script:form.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 225, 230), 1)
        $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $pen.Dispose()
    })
    $script:form.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $s.Close() }
    })
    $script:form.Add_Shown({ param($s, $e) $s.Activate() })

    # --- Nút đóng (X) ---
    $btnX = New-Object System.Windows.Forms.Label
    $btnX.Text      = [string][char]0x2715
    $btnX.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnX.ForeColor = $script:colorGray
    $btnX.BackColor = [System.Drawing.Color]::Transparent
    $btnX.Size      = New-Object System.Drawing.Size(28, 28)
    $btnX.Location  = New-Object System.Drawing.Point(($formW - 28 - 16), 16)
    $btnX.TextAlign = 'MiddleCenter'
    $btnX.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnX.Add_Click({ $script:form.Close() })
    $script:form.Controls.Add($btnX)

    # --- Nhãn nhỏ phía trên ---
    $lblKicker = New-Object System.Windows.Forms.Label
    $lblKicker.Text      = 'T A S K   H Ô M   N A Y'
    $lblKicker.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblKicker.ForeColor = $script:colorAccent
    $lblKicker.BackColor = [System.Drawing.Color]::Transparent
    $lblKicker.AutoSize  = $false
    $lblKicker.Size      = New-Object System.Drawing.Size(300, 20)
    $lblKicker.Location  = New-Object System.Drawing.Point(28, 28)
    $script:form.Controls.Add($lblKicker)

    # --- Con số lớn + dòng phụ ---
    $script:lblBig = New-Object System.Windows.Forms.Label
    $script:lblBig.Font      = New-Object System.Drawing.Font('Segoe UI Light', 42, [System.Drawing.FontStyle]::Regular)
    $script:lblBig.ForeColor = $script:colorInk
    $script:lblBig.BackColor = [System.Drawing.Color]::Transparent
    $script:lblBig.AutoSize  = $false
    $script:lblBig.Size      = New-Object System.Drawing.Size(300, 80)
    $script:lblBig.Location  = New-Object System.Drawing.Point(24, 46)
    $script:form.Controls.Add($script:lblBig)

    $script:lblSub = New-Object System.Windows.Forms.Label
    $script:lblSub.Font      = New-Object System.Drawing.Font('Segoe UI', 11)
    $script:lblSub.ForeColor = $script:colorGray
    $script:lblSub.BackColor = [System.Drawing.Color]::Transparent
    $script:lblSub.AutoSize  = $false
    $script:lblSub.Size      = New-Object System.Drawing.Size(330, 24)
    $script:lblSub.Location  = New-Object System.Drawing.Point(30, 156)
    $script:form.Controls.Add($script:lblSub)

    # --- Đường kẻ ---
    $divider = New-Object System.Windows.Forms.Panel
    $divider.Size      = New-Object System.Drawing.Size(($formW - 56), 1)
    $divider.Location  = New-Object System.Drawing.Point(28, 190)
    $divider.BackColor = $script:colorDivider
    $script:form.Controls.Add($divider)

    # --- Danh sách task ---
    $script:listPanel = New-Object System.Windows.Forms.Panel
    $script:listPanel.Size       = New-Object System.Drawing.Size(($formW - 56), 176)
    $script:listPanel.Location   = New-Object System.Drawing.Point(28, 206)
    $script:listPanel.AutoScroll = $true
    $script:listPanel.BackColor  = $script:colorBg
    $script:form.Controls.Add($script:listPanel)

    $todayTasks   = @($Tasks | Where-Object { -not $_.IsOverdue })
    $overdueTasks = @($Tasks | Where-Object { $_.IsOverdue })

    if ($Tasks.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text      = 'Hôm nay không có việc nào đến hạn hoặc quá hạn.'
        $empty.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
        $empty.ForeColor = $script:colorGray
        $empty.BackColor = [System.Drawing.Color]::Transparent
        $empty.AutoSize  = $false
        $empty.Size      = New-Object System.Drawing.Size(320, 40)
        $empty.Location  = New-Object System.Drawing.Point(0, 8)
        $script:listPanel.Controls.Add($empty)
    }

    if ($todayTasks.Count -gt 0) {
        Add-SectionHeader -Text 'HÔM NAY' -Color $script:colorAccent
        foreach ($t in $todayTasks) { Add-TaskRow -Task $t -IsDemo $IsDemo }
    }
    if ($overdueTasks.Count -gt 0) {
        if ($todayTasks.Count -gt 0) { $script:rowY += 6 }
        Add-SectionHeader -Text 'QUÁ HẠN' -Color $script:colorOverdue
        foreach ($t in $overdueTasks) { Add-TaskRow -Task $t -IsDemo $IsDemo }
    }

    # --- Hai nút chính ---
    $btnW   = 174
    $btnH   = 42
    $btnY   = 396

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text      = 'Mở To Do'
    $btnOpen.Size      = New-Object System.Drawing.Size($btnW, $btnH)
    $btnOpen.Location  = New-Object System.Drawing.Point(28, $btnY)
    $btnOpen.BackColor = $script:colorInk
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.FlatStyle = 'Flat'
    $btnOpen.FlatAppearance.BorderSize = 0
    $btnOpen.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $btnOpen.Cursor    = [System.Windows.Forms.Cursors]::Hand
    Set-RoundedRegion -Control $btnOpen -Radius 8
    $btnOpen.Add_Click({
        # Mở app Microsoft To Do trên máy qua URI protocol; không có app thì mở bản web.
        try {
            Start-Process 'explorer.exe' -ArgumentList 'ms-to-do://' -ErrorAction Stop
        } catch {
            Start-Process 'https://to-do.live.com/tasks/' -ErrorAction SilentlyContinue
        }
    })
    $script:form.Controls.Add($btnOpen)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text      = 'Đã xem'
    $btnClose.Size      = New-Object System.Drawing.Size($btnW, $btnH)
    $btnClose.Location  = New-Object System.Drawing.Point((28 + $btnW + 12), $btnY)
    $btnClose.BackColor = $script:colorBg
    $btnClose.ForeColor = $script:colorInk
    $btnClose.FlatStyle = 'Flat'
    $btnClose.FlatAppearance.BorderSize  = 1
    $btnClose.FlatAppearance.BorderColor = $script:colorDivider
    $btnClose.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnClose.Cursor    = [System.Windows.Forms.Cursors]::Hand
    Set-RoundedRegion -Control $btnClose -Radius 8
    $btnClose.Add_Click({ $script:form.Close() })
    $script:form.Controls.Add($btnClose)

    # --- Liên kết "Nhắc lại sau N phút" ---
    $script:lblSnooze = New-Object System.Windows.Forms.Label
    $script:lblSnooze.Text      = ('Nhắc lại sau {0} phút' -f $script:snoozeMin)
    $script:lblSnooze.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:lblSnooze.ForeColor = $script:colorGray
    $script:lblSnooze.BackColor = [System.Drawing.Color]::Transparent
    $script:lblSnooze.TextAlign = 'MiddleCenter'
    $script:lblSnooze.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $script:lblSnooze.Size      = New-Object System.Drawing.Size(($formW - 56), 22)
    $script:lblSnooze.Location  = New-Object System.Drawing.Point(28, 448)
    $script:lblSnooze.Add_MouseEnter({ param($s, $e) $s.ForeColor = $script:colorInk })
    $script:lblSnooze.Add_MouseLeave({ param($s, $e) $s.ForeColor = $script:colorGray })
    $script:lblSnooze.Add_Click({
        if (-not $script:isDemo) {
            try {
                Register-Snooze -Minutes $script:snoozeMin
            } catch {
                Write-Log ('Không đặt được nhắc lại: ' + $_.Exception.Message)
                [void](Show-Message 'Không đặt được lịch nhắc lại. Bạn thử lại sau nhé.' 'Warning')
                return
            }
        }
        $script:form.Close()
    })
    $script:form.Controls.Add($script:lblSnooze)

    Update-Header

    # --- Cho phép kéo cửa sổ (không có thanh tiêu đề) ---
    $script:dragging = $false
    $dragDown = {
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:dragging  = $true
            $script:dragStart = [System.Windows.Forms.Cursor]::Position
            $script:formStart = $script:form.Location
        }
    }
    $dragMove = {
        if ($script:dragging) {
            $pos = [System.Windows.Forms.Cursor]::Position
            $nx  = $script:formStart.X + ($pos.X - $script:dragStart.X)
            $ny  = $script:formStart.Y + ($pos.Y - $script:dragStart.Y)
            $script:form.Location = New-Object System.Drawing.Point($nx, $ny)
        }
    }
    $dragUp = { $script:dragging = $false }
    foreach ($c in @($script:form, $lblKicker, $script:lblBig, $script:lblSub)) {
        $c.Add_MouseDown($dragDown)
        $c.Add_MouseMove($dragMove)
        $c.Add_MouseUp($dragUp)
    }

    [void]$script:form.ShowDialog()
}

# =====================================================================
# CHẾ ĐỘ ĐĂNG NHẬP
# =====================================================================
function Invoke-LoginMode {
    try {
        Connect-TodoGraph
        $account = (Get-MgContext).Account
        $text = 'Đăng nhập thành công'
        if ($account) { $text = $text + ': ' + $account }
        [void](Show-Message ($text + ".`nTừ giờ ứng dụng sẽ tự nhắc việc cho bạn.") 'Information')
        return 0
    } catch {
        Write-Log ('Đăng nhập lỗi: ' + $_.Exception.Message)
        [void](Show-Message ("Đăng nhập chưa thành công.`n`n" + $_.Exception.Message) 'Error')
        return 1
    }
}

# =====================================================================
# LUỒNG CHÍNH
# =====================================================================
function Invoke-Main {
    $cfg = Get-AppConfig
    Write-Log ('--- Bắt đầu (Force={0}, Snoozed={1}, Login={2}, Demo={3})' -f $Force, $Snoozed, $Login, $Demo)

    if ($Snoozed) {
        # Lần nhắc lại này chỉ chạy 1 lần: xóa lịch ngay.
        Unregister-ScheduledTask -TaskName ($AppName + '-Snooze') -Confirm:$false -ErrorAction SilentlyContinue
    }

    if ($Login) { return (Invoke-LoginMode) }

    $bypass = ($Force -or $Snoozed -or $Demo)
    if (-not $bypass) {
        if ((Get-Date).Hour -ge $cfg.RunUntilHour) {
            Write-Log ('Ngoài khung giờ (chỉ chạy trước {0}h).' -f $cfg.RunUntilHour)
            return 0
        }
        if (Test-ShownToday) {
            Write-Log 'Hôm nay đã hiện rồi.'
            return 0
        }
    }

    if ($Demo) {
        Show-TodoPopup -Tasks (Get-DemoTasks) -Config $cfg -IsDemo $true
        return 0
    }

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Log 'Thiếu module Microsoft.Graph.Authentication.'
        [void](Show-Message "Chưa cài thành phần kết nối Microsoft.`nHãy chạy lại file Cai-dat.bat để cài đặt." 'Warning')
        return 1
    }

    # Mới mở máy thì mạng có thể chưa sẵn sàng: chờ thêm một lúc.
    $attempts = 8
    $delay    = 10
    if ($bypass) { $attempts = 2; $delay = 3 }
    if (-not (Wait-ForNetwork -Attempts $attempts -DelaySeconds $delay)) {
        Write-Log 'Không có kết nối mạng.'
        if ($Force) {
            [void](Show-Message "Không có kết nối Internet.`nHãy kiểm tra mạng rồi thử lại." 'Warning')
        }
        return 1
    }

    $connected = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Connect-TodoGraph
            $connected = $true
            break
        } catch {
            Write-Log ('Đăng nhập lỗi (lần {0}): {1}' -f $attempt, $_.Exception.Message)
            $answer = Show-Message ("Không đăng nhập được Microsoft To Do.`n`nBạn có muốn thử lại không?`n(Nếu lỗi lặp lại, hãy mở 'Đăng nhập lại Microsoft' trong Start Menu.)") 'Warning' 'YesNo'
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { break }
        }
    }
    if (-not $connected) { return 1 }

    try {
        $fetch = Get-TodoTasks -Config $cfg
    } catch {
        Write-Log ('Lỗi khi lấy danh sách: ' + $_.Exception.Message)
        if ($Force) {
            [void](Show-Message ("Không lấy được danh sách việc.`n`n" + $_.Exception.Message) 'Warning')
        }
        return 1
    }

    $tasks = @($fetch.Tasks)
    if ($tasks.Count -eq 0) {
        if ($fetch.ErrorCount -gt 0 -and $Force) {
            [void](Show-Message "Không lấy được việc từ một số danh sách.`nHãy thử lại sau, hoặc xem file nhật ký: $LogPath" 'Warning')
            return 1
        }
        if (-not $Force) {
            Write-Log 'Không có việc nào đến hạn -> không hiện popup.'
            return 0
        }
    }

    if (-not $bypass) { Set-ShownToday }
    Show-TodoPopup -Tasks $tasks -Config $cfg -IsDemo $false
    return 0
}

$mutex    = $null
$hasMutex = $false
$exitCode = 0
try {
    # Chỉ cho 1 popup chạy cùng lúc (tránh hiện đôi khi 2 lịch trùng giờ).
    $mutex    = New-Object System.Threading.Mutex($false, ('Local\' + $AppName))
    $hasMutex = $mutex.WaitOne(0)
    if ($hasMutex) {
        $exitCode = [int](@(Invoke-Main) | Select-Object -Last 1)
    } else {
        Write-Log 'Đang có một cửa sổ khác chạy, bỏ qua.'
    }
} catch {
    Write-Log ('Lỗi không mong muốn: ' + $_.Exception.Message)
    if ($Force -or $Login) {
        [void](Show-Message ("Đã xảy ra lỗi:`n" + $_.Exception.Message) 'Error')
    }
    $exitCode = 1
} finally {
    if ($mutex) {
        if ($hasMutex) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
    }
}
exit $exitCode
