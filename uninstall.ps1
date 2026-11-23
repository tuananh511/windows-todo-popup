#requires -Version 5.1
<#
.SYNOPSIS
    Gỡ cài đặt Windows ToDo Popup: xóa lịch chạy, shortcut, mục trong Settings > Apps và thư mục cài đặt.

.DESCRIPTION
    Thường được gọi qua Go-cai-dat.bat (bản sao chép vào thư mục tạm để có thể tự xóa thư mục cài đặt).
    LƯU Ý: file này PHẢI lưu dạng "UTF-8 with BOM".
#>
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName          = 'WindowsTodoPopup'
$DisplayName      = 'Windows ToDo Popup'
$InstallDir       = Join-Path $env:LOCALAPPDATA $AppName
$RunKeyPath       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$UninstallKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $AppName
$LnkRunNow        = 'Nhắc việc - Chạy ngay.lnk'

function ConvertTo-ConsoleText {
    param([string]$Text)
    $decomposed = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $decomposed.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Replace([string][char]0x0111, 'd').Replace([string][char]0x0110, 'D')
}

$confirm = [System.Windows.Forms.MessageBox]::Show(
    ("Gỡ cài đặt {0}?`n`nLịch tự chạy, shortcut và dữ liệu của chương trình sẽ bị xóa.`n(Danh sách việc trong Microsoft To Do của bạn KHÔNG bị ảnh hưởng.)" -f $DisplayName),
    $DisplayName, 'YesNo', 'Question')
if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }

Write-Host (ConvertTo-ConsoleText 'Đang gỡ cài đặt...')

# 1) Tắt popup đang mở (nếu có) để không bị khóa file
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*WindowsTodoPopup*check_todo.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }

# 2) Xóa lịch chạy (lịch chính + lịch nhắc lại)
foreach ($name in @($AppName, ($AppName + '-Snooze'))) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}

# 3) Xóa mục khởi động cùng Windows (nếu có) và mục trong Settings > Apps
Remove-ItemProperty -Path $RunKeyPath -Name $AppName -ErrorAction SilentlyContinue
Remove-Item -Path $UninstallKeyPath -Recurse -Force -ErrorAction SilentlyContinue

# 4) Xóa shortcut
$desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $LnkRunNow
Remove-Item -LiteralPath $desktopLnk -Force -ErrorAction SilentlyContinue
$startFolder = Join-Path ([Environment]::GetFolderPath('Programs')) $DisplayName
Remove-Item -LiteralPath $startFolder -Recurse -Force -ErrorAction SilentlyContinue

# 5) Xóa thư mục cài đặt (kèm nhật ký và cấu hình)
$leftover = $false
if (Test-Path -LiteralPath $InstallDir) {
    try {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
    } catch {
        $leftover = $true
    }
}
if ($leftover -or (Test-Path -LiteralPath $InstallDir)) {
    # Còn file đang bị khóa: nhờ cmd xóa nốt sau vài giây.
    $cmdArgs = '/c timeout /t 3 /nobreak >nul & rd /s /q "{0}"' -f $InstallDir
    Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -WindowStyle Hidden
}

[void][System.Windows.Forms.MessageBox]::Show(
    ("Đã gỡ cài đặt {0}.`n`nNếu muốn thu hồi quyền truy cập đã cấp cho ứng dụng, xem mục 'Câu hỏi thường gặp' trong README." -f $DisplayName),
    $DisplayName, 'OK', 'Information')
