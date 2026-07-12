# 1. Cấu hình đường dẫn file log để tránh trùng lặp trong ngày
$logPath = "$env:TEMP\todo_am_check.log"
$today = (Get-Date).ToString("yyyy-MM-dd")
$currentHour = (Get-Date).Hour

# 2. KIỂM TRA ĐIỀU KIỆN: Chỉ chạy nếu là khung giờ AM (trước 12h)
if ($currentHour -lt 12) {
    
    # Check xem hôm nay đã bắn thông báo chưa
    if (Test-Path $logPath) {
        $lastRun = Get-Content $logPath
        if ($lastRun -eq $today) { Exit } # Đã chạy rồi thì thoát luôn
    }

    # 3. MÔ PHỎNG CHECK TASK (Thay đoạn này bằng logic đọc API/File của app cụ thể)
    # Giả lập là có task cần làm (True)
    $hasTasks = $true 

    if ($hasTasks) {
        # 4. KHỞI TẠO POP-UP NOTIFICATION CỦA WINDOWS
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
        
        $notification = New-Object System.Windows.Forms.NotifyIcon
        $notification.Icon = [System.Drawing.SystemIcons]::Information
        $notification.BalloonTipIcon = "Info"
        $notification.BalloonTipTitle = "Task Buổi Sáng Chưa Hoàn Thành!"
        $notification.BalloonTipText = "Hôm nay bạn vẫn còn công việc cần giải quyết trong buổi sáng. Check ngay!"
        $notification.Visible = $true
        $notification.ShowBalloonTip(10000) # Hiện trong 10 giây

        # Ghi log lại để lần sau bật máy không bị hiện lại trong cùng ngày
        $today | Out-File $logPath
    }
}