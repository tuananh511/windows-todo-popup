# Windows ToDo Popup

> Remind unfinished morning tasks with lightweight Windows pop-up notifications.

![Release](https://img.shields.io/github/v/release/tuananh511/windows-todo-popup?style=flat-square)
![License](https://img.shields.io/github/license/tuananh511/windows-todo-popup?style=flat-square)
![Build](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)

## Overview
 
AM Task Reminder quét danh sách task trong Microsoft To Do của bạn mỗi buổi sáng, và chỉ hiện thông báo khi có task chưa hoàn thành, đến hạn đúng hôm nay. Không cần cài phần mềm nặng chạy ngầm liên tục — script chỉ chạy 1 lần khi Windows khởi động (qua Task Scheduler) rồi thoát.
 
## Features
 
- **Lấy task thật** từ Microsoft To Do qua Microsoft Graph API (không phải dữ liệu giả lập).
- **Lọc thông minh:** hiện task chưa hoàn thành có hạn hôm nay hoặc đã quá hạn (theo giờ địa phương, đã xử lý đúng timezone), tự động tách riêng 2 nhóm **Hôm nay** / **Quá hạn** và ghi rõ ngày đến hạn ban đầu của từng task quá hạn.
- **Cơ chế chạy bù:** nếu mở máy muộn (9h-10h sáng), script vẫn quét và bắn thông báo bù ngay khi vào Windows.
- **Chống phiền nhiễu:** mỗi ngày chỉ hiện thông báo đúng 1 lần, nhờ ghi log tạm tại `%TEMP%\todo_am_check.log`.
- **Popup phải tự tay tắt:** cửa sổ đứng yên, không tự động biến mất — phải bấm "Đã xem" hoặc "Mở To Do" mới đóng.
- **Giao diện tối giản kiểu Negative Space Design:** nền trắng, nhiều khoảng trắng, con số lớn làm điểm nhấn, không màu mè rối mắt.
- **Nút "Mở To Do"** mở thẳng app Microsoft To Do trên máy để xử lý ngay.
- **0% RAM chạy ngầm** — không có process nào thường trực, script chạy xong tự thoát.
## Installation
 
### 1. Kết nối với Microsoft To Do (làm 1 lần duy nhất)
 
Script cần cài module và đăng nhập 1 lần để được cấp quyền đọc task:
 
```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Connect-MgGraph -Scopes "Tasks.Read" -NoWelcome
```
 
Trình duyệt sẽ mở lên, đăng nhập bằng tài khoản Microsoft đang dùng cho To Do, bấm **Accept** khi được hỏi quyền "đọc task của bạn". Token đăng nhập được lưu cache — các lần script tự chạy sau (kể cả qua Task Scheduler) sẽ không cần đăng nhập lại.
 
### 2. Lưu file đúng chuẩn encoding
 
Để tránh lỗi font tiếng Việt (ký tự lạ, rác font), file `check_todo.ps1` bắt buộc phải lưu đúng chuẩn:
 
1. Mở file bằng **Notepad**.
2. **File → Save As...**
3. Ở mục **Encoding** (góc dưới cửa sổ Save), chọn chính xác: **`UTF-8 with BOM`**.
4. Nhấn **Save**.
### 3. Cấu hình Windows Task Scheduler
 
1. Nhấn phím `Windows`, mở **Task Scheduler**.
2. Ở cột **Actions**, chọn **Create Task...** (không chọn *Basic Task*).
3. **Tab General:**
   - Đặt tên: `Check ToDo AM`.
   - Tích **Run only when user is logged on** (để popup và trình duyệt đăng nhập hiển thị được).
   - Tích **Run with highest privileges**.
4. **Tab Triggers:**
   - **New...** → *Begin the task:* **On a schedule** → **Daily**, giờ bắt đầu **07:00 AM**.
5. **Tab Actions:**
   - **New...** → *Action:* **Start a program**.
   - **Program/script:** `powershell.exe`
   - **Add arguments (optional):**
```
     -ExecutionPolicy Bypass -File "C:\Đường_Dẫn_Của_Bạn\check_todo.ps1"
```
   > ⚠️ Nếu dán nhầm đường dẫn `.ps1` vào ô **Program/script**, Windows sẽ mở file bằng Notepad thay vì chạy script. Ô **Program/script** phải luôn là `powershell.exe`.
6. **Tab Settings:**
   - Tích **"Run task as soon as possible after a scheduled start is missed"** (bật cơ chế chạy bù).
   - Nhấn **OK** để hoàn tất.
## Usage
 
Sau khi cài đặt, script tự chạy mỗi sáng lúc mở máy — không cần thao tác gì thêm.
 
**Để test ngay không cần đợi sáng hôm sau:**
 
1. Xóa file log tạm: `%TEMP%\todo_am_check.log`.
2. Vào **Task Scheduler** → chuột phải task `Check ToDo AM` → **Run**.
3. Popup sẽ hiện với danh sách task thật (due hôm nay) từ Microsoft To Do.
> Nếu test ngoài khung giờ AM (sau 12h trưa), tạm sửa dòng `if ($currentHour -lt 12)` trong script thành `if ($true)`, nhớ đổi lại sau khi test xong.
 
## Roadmap
 
- [ ] Tùy chọn giờ chạy linh hoạt thay vì cố định khung AM.
- [ ] Cho phép tick hoàn thành task trực tiếp trong popup (không cần mở app To Do).
- [ ] Hỗ trợ thêm nguồn task khác (Todoist, Outlook Tasks).
- [ ] Cấu hình bảng màu/theme popup qua file config thay vì sửa code.
## License
 
MIT
