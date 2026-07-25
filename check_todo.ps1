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

        # 4. HIỂN THỊ THÔNG BÁO DẠNG POP-UP PHẢI TỰ TAY TẮT (MessageBox modal)
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

        # MessageBox.Show sẽ đứng yên trên màn hình, chặn luôn cả script
        # cho tới khi người dùng bấm nút OK để đóng.
        [System.Windows.Forms.MessageBox]::Show(
            "Hôm nay bạn vẫn còn công việc cần giải quyết trong buổi sáng. Check ngay!",
            "Task Buổi Sáng Chưa Hoàn Thành!",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1,
            [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly
        )

        # Ghi log lại để lần sau bật máy không bị hiện lại trong cùng ngày
        $today | Out-File $logPath
    }
}
