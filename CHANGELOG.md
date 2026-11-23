# Changelog

Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/), phiên bản theo [SemVer](https://semver.org/lang/vi/).

## [1.0.1] - 2026-11-23

### Sửa lỗi
- Cài đặt dừng ở bước 5 với lỗi `Unable to save shortcut` trên máy Windows có bảng mã ANSI không chứa tiếng Việt: shortcut giờ được lưu bằng tên tạm ASCII rồi đổi tên có dấu.
- Đường dẫn chứa ký tự Unicode (tên người dùng có dấu) được rút gọn 8.3 khi tạo shortcut.
- Cửa sổ cài đặt (console) bị vỡ chữ: nay in không dấu; các hộp thoại vẫn đầy đủ tiếng Việt có dấu.

## [1.0.0] - 2026-11-23

Bản làm lại toàn bộ để **người không rành kỹ thuật cũng cài được bằng 1 cú bấm đúp**.

### Thêm
- `Cai-dat.bat` / `install.ps1`: cài đặt một chạm (không cần admin): sao chép file, cài thành phần Microsoft Graph, đăng nhập, đặt lịch, tạo shortcut, chạy thử.
- `Go-cai-dat.bat` / `uninstall.ps1`: gỡ sạch; có mục trong **Settings > Apps > Installed apps**.
- Shortcut **"Nhắc việc - Chạy ngay"** ngoài Desktop và Start Menu (tham số `-Force`).
- Popup: **tick hoàn thành** ngay trong cửa sổ (đồng bộ lên Microsoft To Do, bỏ tick để hoàn tác).
- Popup: nút/liên kết **"Nhắc lại sau N phút"** (đặt lịch chạy một lần qua Task Scheduler).
- Popup: việc quan trọng (importance = high) hiển thị chữ đậm; tiêu đề dài tự xuống dòng; phím `Esc` để đóng.
- `config.json`: `RunUntilHour`, `ShowOverdue`, `ExcludeLists`, `SnoozeMinutes`, màu sắc.
- Tham số `-Demo` (xem thử không cần đăng nhập), `-Login` (đăng nhập lại).
- CI (GitHub Actions): kiểm tra cú pháp PowerShell 5.1, BOM UTF-8, PSScriptAnalyzer.
- Release tự động: gắn tag `vX.Y.Z` là có file `WindowsTodoPopup.zip`.

### Thay đổi
- Đăng nhập bằng trình duyệt thông thường (dùng lại token đã lưu) thay cho device code vốn không hiện được khi chạy ẩn.
- Lịch chạy: khi đăng nhập Windows (trễ 30 giây) **và** 07:30 mỗi ngày; chạy bù nếu lỡ lịch.
- Nhật ký và trạng thái "đã hiện hôm nay" chuyển sang `%LOCALAPPDATA%\WindowsTodoPopup` (không bị dọn như `%TEMP%`).
- Quyền Microsoft Graph đổi từ `Tasks.Read` sang `Tasks.ReadWrite` (cần cho tính năng tick hoàn thành).
- Chỉ cho một popup chạy cùng lúc.
- Hỗ trợ phân trang khi có nhiều danh sách/việc.

### Sửa lỗi
- Lỗi đăng nhập/mạng giờ hiện thông báo tiếng Việt thay vì im lặng.
- Tiêu đề chứa ký tự `&` không còn bị mất chữ.
