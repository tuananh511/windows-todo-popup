# AM Task Reminder for Windows

Một script PowerShell tối ưu, siêu nhẹ (0% RAM chạy ngầm) giúp tự động kiểm tra danh sách công việc (Task) chưa hoàn thành và bắn thông báo (Pop-up) nhắc nhở vào mỗi buổi sáng khi bạn mở máy tính.

---

## 🎯 Mục đích & Logic hoạt động
*   **Mục đích:** Đảm bảo bạn không bao giờ quên các công việc quan trọng cần giải quyết trong buổi sáng (khung giờ AM) mà không cần phải cài các phần mềm nhắc nhở nặng nề chạy ngầm liên tục.
*   **Logic thông minh:** 
    *   Chỉ kích hoạt thông báo nếu thời gian hiện tại thuộc khung giờ **AM** (trước 12h00 sáng) **VÀ** có task chưa làm.
    *   **Cơ chế chạy bù:** Nếu bạn mở máy muộn (ví dụ 9h - 10h sáng), hệ thống sẽ lập tức quét lịch đã bỏ lỡ và bắn thông báo bù ngay khi vào Windows.
    *   **Tránh phiền nhiễu:** Mỗi ngày hệ thống chỉ bắn thông báo đúng **1 lần duy nhất**. Các lần khởi động máy lại sau đó trong ngày sẽ tự động bỏ qua nhờ cơ chế ghi file log tạm (`%TEMP%\todo_am_check.log`).

---

## ⚠️ Lưu ý quan trọng khi lưu file (Tránh lỗi Font Tiếng Việt)
Để tránh việc thông báo hiển thị bị lỗi font (ký tự lạ, rác font), file script `.ps1` bắt buộc phải được lưu đúng chuẩn mã hóa của Windows PowerShell:

1. Mở file script bằng **Notepad**.
2. Chọn **File** -> **Save As...**
3. Tại mục **Encoding** (nằm ở cạnh dưới cửa sổ, bên trái nút Save), chọn chính xác: **`UTF-8 with BOM`**.
4. Nhấn **Save** để lưu lại.

---

## ⚙️ Hướng dẫn cài đặt với Windows Task Scheduler

Để script tự động chạy mỗi khi mở máy mà không tốn tài nguyên hệ thống, hãy cấu hình thông qua công cụ có sẵn của Windows theo các bước sau:

### Bước 1: Khởi tạo Task
1. Nhấn phím `Windows`, tìm và mở **Task Scheduler**.
2. Ở cột bên phải (Actions), chọn **Create Task...** (Không chọn *Basic Task*).

### Bước 2: Cấu hình các Tab
*   **Tab General:**
    *   Đặt tên tại mục *Name*: `Check ToDo AM`.
    *   Tích chọn **Run only when user is logged on** (Để tránh xung đột quyền và không cần nhập mật khẩu Windows).
    *   Tích chọn **Run with highest privileges** (Chạy với quyền cao nhất).
*   **Tab Triggers (Đặt lịch):**
    *   Nhấn **New...** -> Chọn *Begin the task:* **On a schedule**.
    *   Chọn mục **Daily** (Hàng ngày), đặt thời gian bắt đầu là **07:00 AM**. Nhấn **OK**.
*   **Tab Actions (Kích hoạt script):**
    *   Nhấn **New...** -> Chọn *Action:* **Start a program**.
    *   Tại ô *Program/script*, gõ: `powershell.exe`
    *   Tại ô *Add arguments (optional)*, dán chính xác dòng sau (Bắt buộc có tham số Bypass để Windows không chặn script):
        ```text
        -ExecutionPolicy Bypass -File "C:\Đường_Dẫn_Của_Bạn\check_todo.ps1"
        ```
    *   Nhấn **OK**.
*   **Tab Settings (Cấu hình chạy bù):**
    *   Tích chọn mục: **"Run task as soon as possible after a scheduled start is missed"**. *(Đây là tùy chọn quyết định giúp hệ thống tự động chạy bù vào lúc 9-10h sáng nếu lúc 7h sáng máy đang tắt).*
    *   Nhấn **OK** để hoàn tất.

---
## 🧪 Cách kiểm tra trực tiếp
Để kiểm tra hệ thống hoạt động chuẩn chưa mà không cần đợi đến sáng hôm sau:
1. Vào **Task Scheduler**, tìm task `Check ToDo AM` vừa tạo.
2. Chuột phải vào tác vụ và chọn **Run**. 
3. Thông báo tiếng Việt chuẩn font sẽ lập tức xuất hiện ở góc phải màn hình.
