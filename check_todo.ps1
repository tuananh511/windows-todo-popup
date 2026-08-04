# =====================================================================
# CẤU HÌNH
# =====================================================================
$logPath   = "$env:TEMP\todo_am_check.log"
$today     = (Get-Date).ToString("yyyy-MM-dd")
$currentHour = (Get-Date).Hour

# =====================================================================
# 1. CHỈ CHẠY NẾU LÀ KHUNG GIỜ AM (trước 12h)
# =====================================================================
if ($currentHour -lt 12) {

    if (Test-Path $logPath) {
        $lastRun = Get-Content $logPath
        if ($lastRun -eq $today) { Exit }   # Đã chạy rồi thì thoát luôn
    }

    # =====================================================================
    # 2. LẤY TASK THẬT TỪ MICROSOFT TO DO (qua Microsoft Graph)
    # =====================================================================
    $debugLog = "$env:TEMP\todo_am_debug.log"
    function Write-DebugLog($msg) {
        "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $msg" | Out-File -Append -FilePath $debugLog
    }

    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Write-DebugLog "Module version: $((Get-Module Microsoft.Graph.Authentication).Version)"

        # Thử kết nối tối đa 3 lần, cách nhau 15s (phòng lúc mới mở máy mạng/trình duyệt chưa sẵn sàng).
        $connected = $false
        for ($i = 1; $i -le 3 -and -not $connected; $i++) {
            try {
                Connect-MgGraph -Scopes "Tasks.Read" -NoWelcome -ErrorAction Stop
                $connected = $true
                Write-DebugLog "Connect-MgGraph OK (lan $i). Account: $((Get-MgContext).Account)"
            } catch {
                Write-DebugLog "Connect-MgGraph FAILED (lan $i): $($_.Exception.Message)"
                if ($i -lt 3) { Start-Sleep -Seconds 15 }
            }
        }
        if (-not $connected) {
            Write-DebugLog "Bo qua: khong the dang nhap Graph sau 3 lan thu. Se thu lai vao lan mo may/chay task tiep theo."
            Exit
        }
    } catch {
        Write-DebugLog "Loi khi import module: $($_.Exception.Message)"
        Exit
    }

    try {
        $lists = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me/todo/lists").value
        Write-DebugLog "So list lay duoc: $($lists.Count)"
    } catch {
        Write-DebugLog "Loi khi lay danh sach list: $($_.Exception.Message)"
        Exit
    }

    # Hàm quy đổi due date của Graph API (theo UTC hoặc timezone ghi trong field) sang giờ địa phương thật sự
    function Convert-GraphDueDate($dueDateTime) {
        if (-not $dueDateTime -or -not $dueDateTime.dateTime) { return $null }
        $raw = [datetime]::Parse($dueDateTime.dateTime, [System.Globalization.CultureInfo]::InvariantCulture)
        $tzId = $dueDateTime.timeZone
        try {
            if ($tzId -eq "UTC") {
                $utc = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Utc)
            } else {
                $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($tzId)
                $unspecified = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Unspecified)
                $utc = [System.TimeZoneInfo]::ConvertTimeToUtc($unspecified, $tz)
            }
        } catch {
            $utc = [datetime]::SpecifyKind($raw, [System.DateTimeKind]::Utc)
        }
        return $utc.ToLocalTime().Date
    }

    $todayDate = (Get-Date).Date
    $tasks = @()
    foreach ($list in $lists) {
        $encodedFilter = [uri]::EscapeDataString("status ne 'completed'")
        $uri = "https://graph.microsoft.com/v1.0/me/todo/lists/$($list.id)/tasks?`$filter=$encodedFilter&`$top=100"
        $rawCountThisList = 0

        try {
            # Lặp qua TẤT CẢ các trang kết quả (Graph API trả về theo trang, không trả hết 1 lần)
            while ($uri) {
                $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
                $rawCountThisList += $resp.value.Count
                foreach ($t in $resp.value) {
                    # Lấy task có due date HÔM NAY hoặc ĐÃ QUÁ HẠN (đặt lịch trước đó nhưng chưa làm).
                    # Bỏ qua task không có due date, và bỏ qua task có hạn trong tương lai.
                    $dueDate = Convert-GraphDueDate $t.dueDateTime
                    if ($dueDate -and $dueDate -le $todayDate) {
                        $tasks += [PSCustomObject]@{
                            Title     = $t.title
                            DueDate   = $dueDate
                            IsOverdue = ($dueDate -lt $todayDate)
                        }
                    }
                }
                $uri = $resp.'@odata.nextLink'
            }
            Write-DebugLog "List '$($list.displayName)': $rawCountThisList task chua completed (truoc khi loc due date)"
        } catch {
            Write-DebugLog "Loi khi fetch task cho list '$($list.displayName)': $($_.Exception.Message)"
        }
    }

    # Task hôm nay hiện trước, task quá hạn xếp theo hạn cũ nhất lên đầu
    # Bọc @() để tránh bug PowerShell: pipe mảng rỗng qua Sort-Object sẽ trả về $null thay vì mảng rỗng,
    # khiến $tasks.Count phía dưới bị sai/rỗng và popup không bao giờ hiện dù có task.
    $tasks = @($tasks | Sort-Object IsOverdue, DueDate)

    $hasTasks = $tasks.Count -gt 0
    Write-DebugLog "Tong task hop le (hom nay + qua han): $($tasks.Count)"

    if ($hasTasks) {

        # =====================================================================
        # 3. GIAO DIỆN POPUP - PHONG CÁCH "NEGATIVE SPACE DESIGN"
        #    (nền trắng/xám trung tính, nhiều khoảng trắng, typography làm điểm nhấn,
        #     1 màu accent duy nhất, tối giản, không gradient/grain)
        # =====================================================================
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        # --- Hàm tạo vùng bo góc nhẹ cho control ---
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

        # --- Bảng màu trung tính ---
        $colorBg        = [System.Drawing.Color]::FromArgb(255, 255, 255)   # trắng
        $colorInk       = [System.Drawing.Color]::FromArgb(17, 17, 20)      # gần đen
        $colorGray      = [System.Drawing.Color]::FromArgb(140, 140, 148)   # xám nhạt (subtext)
        $colorDivider   = [System.Drawing.Color]::FromArgb(232, 232, 236)   # xám rất nhạt (đường kẻ)
        $colorAccent    = [System.Drawing.Color]::FromArgb(0, 120, 212)     # xanh accent (Microsoft blue)
        $colorOverdue   = [System.Drawing.Color]::FromArgb(196, 90, 78)     # đỏ gạch trầm (cho task quá hạn)

        $formW = 420
        $formH = 400

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Nhắc việc buổi sáng"
        $form.Size = New-Object System.Drawing.Size($formW, $formH)
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "None"
        $form.TopMost = $true
        $form.BackColor = $colorBg
        Set-RoundedRegion -Control $form -Radius 10

        # Viền mỏng bao quanh form để tách nền trắng ra khỏi desktop (vẫn giữ tối giản)
        $form.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 225, 230), 1)
            $e.Graphics.DrawRectangle($pen, 0, 0, ($form.Width - 1), ($form.Height - 1))
            $pen.Dispose()
        })

        # --- Nút đóng (X) góc trên phải, tối giản ---
        $closeSize = 28
        $closeX = $formW - $closeSize - 16
        $btnX = New-Object System.Windows.Forms.Label
        $btnX.Text = "✕"
        $btnX.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $btnX.ForeColor = $colorGray
        $btnX.BackColor = [System.Drawing.Color]::Transparent
        $btnX.Size = New-Object System.Drawing.Size($closeSize, $closeSize)
        $btnX.Location = New-Object System.Drawing.Point($closeX, 16)
        $btnX.TextAlign = "MiddleCenter"
        $btnX.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnX.Add_Click({ $form.Close() })
        $form.Controls.Add($btnX)

        # --- Nhãn nhỏ phía trên (kicker, kiểu tech dashboard) ---
        $lblKicker = New-Object System.Windows.Forms.Label
        $lblKicker.Text = "T A S K   H Ô M   N A Y"
        $lblKicker.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $lblKicker.ForeColor = $colorAccent
        $lblKicker.BackColor = [System.Drawing.Color]::Transparent
        $lblKicker.AutoSize = $false
        $lblKicker.Size = New-Object System.Drawing.Size(300, 20)
        $lblKicker.Location = New-Object System.Drawing.Point(28, 28)
        $form.Controls.Add($lblKicker)

        # --- Con số lớn + subtext (điểm nhấn typography) ---
        $lblBig = New-Object System.Windows.Forms.Label
        $lblBig.Text = "$($tasks.Count)"
        $lblBig.Font = New-Object System.Drawing.Font("Segoe UI Light", 42, [System.Drawing.FontStyle]::Regular)
        $lblBig.ForeColor = $colorInk
        $lblBig.BackColor = [System.Drawing.Color]::Transparent
        $lblBig.AutoSize = $false
        $lblBig.Size = New-Object System.Drawing.Size(300, 80)
        $lblBig.Location = New-Object System.Drawing.Point(24, 46)
        $form.Controls.Add($lblBig)

        $lblSub = New-Object System.Windows.Forms.Label
        $lblSub.Text = "việc chưa hoàn thành"
        $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        $lblSub.ForeColor = $colorGray
        $lblSub.BackColor = [System.Drawing.Color]::Transparent
        $lblSub.AutoSize = $false
        $lblSub.Size = New-Object System.Drawing.Size(300, 24)
        $lblSub.Location = New-Object System.Drawing.Point(30, 156)
        $form.Controls.Add($lblSub)

        # --- Đường kẻ phân cách mỏng ---
        $divider1 = New-Object System.Windows.Forms.Panel
        $divider1.Size = New-Object System.Drawing.Size(($formW - 56), 1)
        $divider1.Location = New-Object System.Drawing.Point(28, 190)
        $divider1.BackColor = $colorDivider
        $form.Controls.Add($divider1)

        # --- Danh sách task: tách nhóm "HÔM NAY" và "QUÁ HẠN" (kèm ngày hạn cũ) ---
        $listPanel = New-Object System.Windows.Forms.Panel
        $listPanel.Size = New-Object System.Drawing.Size(($formW - 56), 130)
        $listPanel.Location = New-Object System.Drawing.Point(28, 206)
        $listPanel.AutoScroll = $true
        $listPanel.BackColor = $colorBg
        $form.Controls.Add($listPanel)

        $todayTasks   = @($tasks | Where-Object { -not $_.IsOverdue })
        $overdueTasks = @($tasks | Where-Object { $_.IsOverdue })

        $script:rowY = 0
        $idx = 1

        function Add-SectionHeader {
            param($Text, $Color)
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $Text
            $lbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
            $lbl.ForeColor = $Color
            $lbl.BackColor = [System.Drawing.Color]::Transparent
            $lbl.AutoSize = $false
            $lbl.Size = New-Object System.Drawing.Size(300, 18)
            $lbl.Location = New-Object System.Drawing.Point(0, $script:rowY)
            $listPanel.Controls.Add($lbl)
            $script:rowY += 24
        }

        if ($todayTasks.Count -gt 0) {
            Add-SectionHeader -Text "HÔM NAY" -Color $colorAccent
            foreach ($t in $todayTasks) {
                $lblIdx = New-Object System.Windows.Forms.Label
                $lblIdx.Text = "{0:D2}" -f $idx
                $lblIdx.Font = New-Object System.Drawing.Font("Segoe UI", 9)
                $lblIdx.ForeColor = $colorGray
                $lblIdx.BackColor = [System.Drawing.Color]::Transparent
                $lblIdx.Size = New-Object System.Drawing.Size(28, 22)
                $lblIdx.Location = New-Object System.Drawing.Point(0, $script:rowY)
                $listPanel.Controls.Add($lblIdx)

                $lblTask = New-Object System.Windows.Forms.Label
                $lblTask.Text = $t.Title
                $lblTask.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
                $lblTask.ForeColor = $colorInk
                $lblTask.BackColor = [System.Drawing.Color]::Transparent
                $lblTask.AutoSize = $false
                $lblTask.Size = New-Object System.Drawing.Size(300, 22)
                $lblTask.Location = New-Object System.Drawing.Point(32, $script:rowY)
                $listPanel.Controls.Add($lblTask)

                $script:rowY += 30
                $idx++
            }
        }

        if ($overdueTasks.Count -gt 0) {
            $script:rowY += 8
            Add-SectionHeader -Text "QUÁ HẠN" -Color $colorOverdue
            foreach ($t in $overdueTasks) {
                $lblIdx = New-Object System.Windows.Forms.Label
                $lblIdx.Text = "{0:D2}" -f $idx
                $lblIdx.Font = New-Object System.Drawing.Font("Segoe UI", 9)
                $lblIdx.ForeColor = $colorGray
                $lblIdx.BackColor = [System.Drawing.Color]::Transparent
                $lblIdx.Size = New-Object System.Drawing.Size(28, 22)
                $lblIdx.Location = New-Object System.Drawing.Point(0, $script:rowY)
                $listPanel.Controls.Add($lblIdx)

                $lblTask = New-Object System.Windows.Forms.Label
                $lblTask.Text = $t.Title
                $lblTask.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
                $lblTask.ForeColor = $colorInk
                $lblTask.BackColor = [System.Drawing.Color]::Transparent
                $lblTask.AutoSize = $false
                $lblTask.Size = New-Object System.Drawing.Size(300, 20)
                $lblTask.Location = New-Object System.Drawing.Point(32, $script:rowY)
                $listPanel.Controls.Add($lblTask)

                $lblDue = New-Object System.Windows.Forms.Label
                $lblDue.Text = "Quá hạn từ " + $t.DueDate.ToString("dd/MM/yyyy")
                $lblDue.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
                $lblDue.ForeColor = $colorOverdue
                $lblDue.BackColor = [System.Drawing.Color]::Transparent
                $lblDue.AutoSize = $false
                $lblDue.Size = New-Object System.Drawing.Size(300, 16)
                $dueY = $script:rowY + 20
                $lblDue.Location = New-Object System.Drawing.Point(32, $dueY)
                $listPanel.Controls.Add($lblDue)

                $script:rowY += 44
                $idx++
            }
        }

        # --- Nút "Mở To Do" (mở app Microsoft To Do thật trên máy, không phải web) ---
        $btnW = 174
        $btnH = 42
        $btnGap = 12
        $btnY = $formH - $btnH - 26

        $btnOpenTodo = New-Object System.Windows.Forms.Button
        $btnOpenTodo.Text = "Mở To Do"
        $btnOpenTodo.Size = New-Object System.Drawing.Size($btnW, $btnH)
        $btnOpenTodo.Location = New-Object System.Drawing.Point(28, $btnY)
        $btnOpenTodo.BackColor = $colorInk
        $btnOpenTodo.ForeColor = [System.Drawing.Color]::White
        $btnOpenTodo.FlatStyle = "Flat"
        $btnOpenTodo.FlatAppearance.BorderSize = 0
        $btnOpenTodo.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
        $btnOpenTodo.Cursor = [System.Windows.Forms.Cursors]::Hand
        Set-RoundedRegion -Control $btnOpenTodo -Radius 8
        $btnOpenTodo.Add_Click({
            # Mở app Microsoft To Do đã cài trên máy qua URI protocol.
            # Dùng explorer.exe làm trung gian để tránh lỗi khi gọi trực tiếp Start-Process với URI.
            try {
                Start-Process "explorer.exe" -ArgumentList "ms-to-do://" -ErrorAction Stop
            } catch {
                Start-Process "https://to-do.live.com/tasks/" -ErrorAction SilentlyContinue
            }
        })
        $form.Controls.Add($btnOpenTodo)

        $btnCloseX = 28 + $btnW + $btnGap
        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = "Đã xem"
        $btnClose.Size = New-Object System.Drawing.Size($btnW, $btnH)
        $btnClose.Location = New-Object System.Drawing.Point($btnCloseX, $btnY)
        $btnClose.BackColor = $colorBg
        $btnClose.ForeColor = $colorInk
        $btnClose.FlatStyle = "Flat"
        $btnClose.FlatAppearance.BorderSize = 1
        $btnClose.FlatAppearance.BorderColor = $colorDivider
        $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
        Set-RoundedRegion -Control $btnClose -Radius 8
        $btnClose.Add_Click({ $form.Close() })
        $form.Controls.Add($btnClose)

        # Cho phép kéo cửa sổ đi vì không có thanh tiêu đề (FormBorderStyle = None)
        $form.Add_MouseDown({
            param($s, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                $script:dragging = $true
                $script:dragStart = [System.Windows.Forms.Cursor]::Position
                $script:formStart = $form.Location
            }
        })
        $form.Add_MouseMove({
            if ($script:dragging) {
                $diffX = [System.Windows.Forms.Cursor]::Position.X - $script:dragStart.X
                $diffY = [System.Windows.Forms.Cursor]::Position.Y - $script:dragStart.Y
                $newX = $script:formStart.X + $diffX
                $newY = $script:formStart.Y + $diffY
                $form.Location = New-Object System.Drawing.Point($newX, $newY)
            }
        })
        $form.Add_MouseUp({ $script:dragging = $false })

        [void]$form.ShowDialog()

        $today | Out-File $logPath
    }
}
