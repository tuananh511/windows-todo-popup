#requires -Version 5.1
<#
.SYNOPSIS
    Trình cài đặt Windows ToDo Popup (không cần quyền admin).

.DESCRIPTION
    Người dùng chỉ cần bấm đúp Cai-dat.bat, file này sẽ làm toàn bộ việc còn lại:
      1. Sao chép chương trình vào %LOCALAPPDATA%\WindowsTodoPopup
      2. Cài thành phần Microsoft Graph (nếu máy chưa có)
      3. Đăng nhập Microsoft (trình duyệt tự mở)
      4. Đặt lịch tự chạy (khi đăng nhập Windows + 07:30 mỗi ngày)
      5. Tạo shortcut (Desktop, Start Menu) và mục "Gỡ cài đặt" trong Settings > Apps
      6. Chạy thử popup

    LƯU Ý: file này PHẢI lưu dạng "UTF-8 with BOM" (xem README, mục Dành cho nhà phát triển).
#>
[CmdletBinding()]
param(
    [string]$DailyTime = '07:30'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName          = 'WindowsTodoPopup'
$DisplayName      = 'Windows ToDo Popup'
$RepoUrl          = 'https://github.com/tuananh511/windows-todo-popup'
$InstallDir       = Join-Path $env:LOCALAPPDATA $AppName
$SourceDir        = $PSScriptRoot
$RunKeyPath       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$UninstallKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $AppName
$TotalSteps       = 6

# Tên shortcut (dùng chung với uninstall.ps1)
$LnkRunNow   = 'Nhắc việc - Chạy ngay.lnk'
$LnkLogin    = 'Đăng nhập lại Microsoft.lnk'
$LnkSettings = 'Cài đặt (mở config.json).lnk'
$LnkRemove   = 'Gỡ cài đặt.lnk'

# Console Windows hay thiếu font tiếng Việt -> chỉ in ra console dạng KHÔNG DẤU.
# (Các hộp thoại MessageBox vẫn hiển thị đầy đủ tiếng Việt có dấu.)
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

# WScript.Shell chỉ làm việc với bảng mã ANSI: đường dẫn có ký tự Unicode (tên người dùng có dấu)
# sẽ hỏng -> dùng đường dẫn rút gọn 8.3 nếu có thể.
function Get-SafePath {
    param([string]$Path)
    if ($Path -notmatch '[^\x00-\x7F]') { return $Path }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path -LiteralPath $Path -PathType Container) { return $fso.GetFolder($Path).ShortPath }
        return $fso.GetFile($Path).ShortPath
    } catch {
        return $Path
    }
}

function Write-Step {
    param([int]$Index, [string]$Text)
    Write-Host ''
    Write-Host (ConvertTo-ConsoleText ('[{0}/{1}] {2}' -f $Index, $TotalSteps, $Text)) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host (ConvertTo-ConsoleText ('      OK - ' + $Text)) -ForegroundColor Green
}

function Write-Note {
    param([string]$Text)
    Write-Host (ConvertTo-ConsoleText ('      ' + $Text)) -ForegroundColor Gray
}

function New-AppShortcut {
    param(
        [string]$Path,
        [string]$Target,
        [string]$Arguments,
        [string]$Description,
        [string]$WorkingDirectory
    )
    # WScript.Shell không lưu được tên file có dấu tiếng Việt (ANSI) -> lưu tên tạm ASCII rồi đổi tên.
    $folder   = Split-Path -Parent $Path
    $tempPath = Join-Path $folder ('wtp-' + [guid]::NewGuid().ToString('N') + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($tempPath)
    $sc.TargetPath       = $Target
    $sc.Arguments        = $Arguments
    $sc.Description      = (ConvertTo-ConsoleText $Description)
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.WindowStyle      = 7   # thu nhỏ, giảm nháy cửa sổ
    $sc.Save()
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

try {
    Write-Host ''
    Write-Host (ConvertTo-ConsoleText ('=== Cài đặt {0} ===' -f $DisplayName)) -ForegroundColor White

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        ("Cài đặt {0}?`n`nChương trình sẽ hiện một popup nhắc các việc Microsoft To Do đến hạn hôm nay mỗi sáng.`nKhông cần quyền quản trị (admin)." -f $DisplayName),
        $DisplayName, 'OKCancel', 'Question')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host (ConvertTo-ConsoleText 'Đã hủy.')
        exit 0
    }

    # ------------------------------------------------------------------
    Write-Step 1 'Sao chép chương trình...'
    # ------------------------------------------------------------------
    $version = '1.0.0'
    $versionFile = Join-Path $SourceDir 'VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        $version = ([System.IO.File]::ReadAllText($versionFile)).Trim()
    }

    $required = @('check_todo.ps1', 'uninstall.ps1', 'Go-cai-dat.bat', 'config.json')
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $name))) {
            throw ("Thiếu file '{0}'. Hãy giải nén ĐẦY ĐỦ file zip (chuột phải > Extract All) rồi chạy lại Cai-dat.bat." -f $name)
        }
    }

    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $sameFolder = ([System.IO.Path]::GetFullPath($SourceDir).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\'))
    if (-not $sameFolder) {
        foreach ($name in @('check_todo.ps1', 'uninstall.ps1', 'Go-cai-dat.bat', 'VERSION', 'LICENSE')) {
            $src = Join-Path $SourceDir $name
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $name) -Force
            }
        }
        # Giữ nguyên config.json cũ của người dùng khi cài đè phiên bản mới.
        $cfgDest = Join-Path $InstallDir 'config.json'
        if (-not (Test-Path -LiteralPath $cfgDest)) {
            Copy-Item -LiteralPath (Join-Path $SourceDir 'config.json') -Destination $cfgDest -Force
        }
    }

    # Gỡ dấu "tải từ Internet" để Windows không hỏi cảnh báo khi chạy.
    Get-ChildItem -LiteralPath $InstallDir -File | Unblock-File -ErrorAction SilentlyContinue
    Write-Ok ('Đã cài vào ' + $InstallDir)

    # ------------------------------------------------------------------
    Write-Step 2 'Kiểm tra thành phần kết nối Microsoft...'
    # ------------------------------------------------------------------
    if (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication) {
        Write-Ok 'Máy đã có sẵn.'
    } else {
        Write-Note 'Đang tải và cài đặt (khoảng 1 phút, cần Internet)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        } catch {
            # Không sao: Install-Module -Force sẽ tự xử lý tiếp.
        }
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
        Write-Ok 'Đã cài xong.'
    }

    # ------------------------------------------------------------------
    Write-Step 3 'Đăng nhập Microsoft...'
    # ------------------------------------------------------------------
    Write-Note 'Trình duyệt sẽ tự mở. Hãy đăng nhập tài khoản Microsoft bạn dùng cho To Do,'
    Write-Note "rồi bấm 'Chấp nhận' (Accept) để cho phép đọc và đánh dấu hoàn thành việc."
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Connect-MgGraph -Scopes 'Tasks.ReadWrite' -NoWelcome -ErrorAction Stop
    $account = (Get-MgContext).Account
    if ($account) { Write-Ok ('Đã đăng nhập: ' + $account) } else { Write-Ok 'Đã đăng nhập.' }

    # ------------------------------------------------------------------
    Write-Step 4 'Đặt lịch tự chạy...'
    # ------------------------------------------------------------------
    $user       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $scriptPath = Join-Path $InstallDir 'check_todo.ps1'
    $argument   = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
    $action     = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -WorkingDirectory $InstallDir
    $settings   = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 12)
    $principal  = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $daily      = New-ScheduledTaskTrigger -Daily -At $DailyTime
    $logon      = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logon.Delay = 'PT30S'
    $description = 'Nhắc việc Microsoft To Do mỗi sáng. ' + $RepoUrl

    $useRunKey = $false
    try {
        Register-ScheduledTask -TaskName $AppName -Action $action -Trigger @($logon, $daily) -Settings $settings -Principal $principal -Description $description -Force | Out-Null
        Write-Ok ('Tự chạy khi đăng nhập Windows và lúc ' + $DailyTime + ' mỗi ngày.')
    } catch {
        # Một số máy không cho người dùng thường tạo lịch "khi đăng nhập": dùng khóa Run thay thế.
        $useRunKey = $true
        Write-Note ('Không tạo được lịch khi đăng nhập (' + $_.Exception.Message + '). Dùng cách khác...')
        Register-ScheduledTask -TaskName $AppName -Action $action -Trigger $daily -Settings $settings -Principal $principal -Description $description -Force | Out-Null
        Write-Ok ('Tự chạy lúc ' + $DailyTime + ' mỗi ngày.')
    }

    if ($useRunKey) {
        $runCommand = 'powershell.exe {0}' -f $argument
        Set-ItemProperty -Path $RunKeyPath -Name $AppName -Value $runCommand
        Write-Ok 'Tự chạy khi đăng nhập Windows (qua mục khởi động của người dùng).'
    } else {
        Remove-ItemProperty -Path $RunKeyPath -Name $AppName -ErrorAction SilentlyContinue
    }

    # ------------------------------------------------------------------
    Write-Step 5 'Tạo shortcut và mục Gỡ cài đặt...'
    # ------------------------------------------------------------------
    $psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $safeDir     = Get-SafePath $InstallDir
    $safeScript  = Get-SafePath $scriptPath
    $runNowArgs  = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Force' -f $safeScript
    $loginArgs   = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Login' -f $safeScript
    $configPath  = Get-SafePath (Join-Path $InstallDir 'config.json')
    $removeBat   = Get-SafePath (Join-Path $InstallDir 'Go-cai-dat.bat')

    $desktop = [Environment]::GetFolderPath('Desktop')
    New-AppShortcut -Path (Join-Path $desktop $LnkRunNow) -Target $psExe -Arguments $runNowArgs -Description 'Xem ngay các việc cần làm hôm nay' -WorkingDirectory $safeDir

    $startFolder = Join-Path ([Environment]::GetFolderPath('Programs')) $DisplayName
    if (-not (Test-Path -LiteralPath $startFolder)) { New-Item -ItemType Directory -Path $startFolder -Force | Out-Null }
    New-AppShortcut -Path (Join-Path $startFolder $LnkRunNow)   -Target $psExe -Arguments $runNowArgs -Description 'Xem ngay các việc cần làm hôm nay' -WorkingDirectory $safeDir
    New-AppShortcut -Path (Join-Path $startFolder $LnkLogin)    -Target $psExe -Arguments $loginArgs  -Description 'Đăng nhập lại tài khoản Microsoft' -WorkingDirectory $safeDir
    New-AppShortcut -Path (Join-Path $startFolder $LnkSettings) -Target (Join-Path $env:SystemRoot 'System32\notepad.exe') -Arguments ('"{0}"' -f $configPath) -Description 'Mở file cấu hình bằng Notepad' -WorkingDirectory $safeDir
    New-AppShortcut -Path (Join-Path $startFolder $LnkRemove)   -Target $removeBat -Arguments '' -Description 'Gỡ cài đặt Windows ToDo Popup' -WorkingDirectory $safeDir

    # Hiện trong Settings > Apps > Installed apps
    New-Item -Path $UninstallKeyPath -Force | Out-Null
    $stringValues = @{
        DisplayName     = $DisplayName
        DisplayVersion  = $version
        Publisher       = 'tuananh511'
        InstallLocation = $InstallDir
        UninstallString = ('"{0}"' -f $removeBat)
        URLInfoAbout    = $RepoUrl
    }
    foreach ($key in $stringValues.Keys) {
        New-ItemProperty -Path $UninstallKeyPath -Name $key -Value $stringValues[$key] -PropertyType String -Force | Out-Null
    }
    New-ItemProperty -Path $UninstallKeyPath -Name 'NoModify' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $UninstallKeyPath -Name 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Ok 'Đã tạo shortcut ngoài Desktop và trong Start Menu.'

    # ------------------------------------------------------------------
    Write-Step 6 'Chạy thử popup...'
    # ------------------------------------------------------------------
    Start-Process -FilePath $psExe -ArgumentList $runNowArgs -WindowStyle Hidden
    Write-Ok 'Popup sẽ hiện trong vài giây.'

    Write-Host ''
    Write-Host (ConvertTo-ConsoleText 'HOÀN TẤT!') -ForegroundColor Green

    [void][System.Windows.Forms.MessageBox]::Show(
        ("Cài đặt xong!`n`n- Từ giờ mỗi sáng, popup sẽ tự hiện nếu bạn có việc đến hạn.`n- Cần xem ngay? Bấm shortcut 'Nhắc việc - Chạy ngay' ngoài Desktop.`n- Popup vừa hiện để bạn xem thử. Nếu thấy số 0 thì hôm nay bạn chưa có việc nào đến hạn trong To Do, vẫn là bình thường."),
        $DisplayName, 'OK', 'Information')
}
catch {
    $reason = $_.Exception.Message
    Write-Host ''
    Write-Host (ConvertTo-ConsoleText ('LỖI: ' + $reason)) -ForegroundColor Red
    [void][System.Windows.Forms.MessageBox]::Show(
        ("Cài đặt chưa hoàn tất.`n`nLý do: {0}`n`nBạn thử chạy lại Cai-dat.bat. Nếu vẫn lỗi, hãy chụp màn hình cửa sổ này và gửi cho người hỗ trợ." -f $reason),
        $DisplayName, 'OK', 'Error')
    exit 1
}
