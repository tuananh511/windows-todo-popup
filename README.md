# Windows ToDo Popup

> Remind unfinished morning tasks with lightweight Windows pop-up notifications.

![Release](https://img.shields.io/github/v/release/tuananh511/windows-todo-popup?style=flat-square)
![License](https://img.shields.io/github/license/tuananh511/windows-todo-popup?style=flat-square)
![Build](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)

## Overview

Windows ToDo Popup là một script PowerShell tối ưu, siêu nhẹ (0% RAM chạy ngầm), tự động kiểm tra danh sách công việc (Task) chưa hoàn thành và bắn thông báo (Pop-up) nhắc nhở vào mỗi buổi sáng khi bạn mở máy tính. Không cần cài thêm phần mềm nhắc nhở nặng nề chạy nền liên tục.

## Features

- Chỉ kích hoạt thông báo nếu thời gian hiện tại thuộc khung giờ AM (trước 12h00 sáng) **và** còn task chưa làm
- Cơ chế chạy bù: nếu bạn mở máy muộn (ví dụ 9h - 10h sáng), hệ thống lập tức quét lịch đã bỏ lỡ và bắn thông báo bù ngay khi vào Windows
- Tránh phiền nhiễu: mỗi ngày chỉ bắn thông báo đúng 1 lần duy nhất, nhờ cơ chế ghi file log tạm (`%TEMP%\todo_am_check.log`)
- Hiển thị đúng font tiếng Việt trong thông báo (khi lưu file đúng chuẩn UTF-8 with BOM)
- Chạy hoàn toàn qua Windows Task Scheduler có sẵn, không tốn tài nguyên hệ thống

## Installation

1. Tải file `check_todo.ps1` về máy.
2. Mở file bằng **Notepad**, chọn **File → Save As...**, tại mục **Encoding** chọn chính xác **`UTF-8 with BOM`**, sau đó **Save** (bắt buộc để tránh lỗi font tiếng Việt).
3. Mở **Task Scheduler** (nhấn `Windows`, tìm "Task Scheduler").
4. Ở cột **Actions**, chọn **Create Task...** (không chọn *Basic Task*).
5. Cấu hình các tab:
   - **General:** đặt tên `Check ToDo AM`; tích **Run only when user is logged on**; tích **Run with highest privileges**.
   - **Triggers:** **New...** → *Begin the task:* **On a schedule** → **Daily**, giờ bắt đầu **07:00 AM**.
   - **Actions:** **New...** → *Action:* **Start a program** → *Program/script:* `powershell.exe` → *Add arguments:*
     ```
     -ExecutionPolicy Bypass -File "C:\Đường_Dẫn_Của_Bạn\check_todo.ps1"
     ```
   - **Settings:** tích **"Run task as soon as possible after a scheduled start is missed"** (giúp chạy bù nếu máy tắt lúc 7h sáng).

## Usage

- Task chạy tự động mỗi sáng lúc 07:00, hoặc chạy bù ngay khi bạn mở máy nếu đã bỏ lỡ giờ hẹn.
- Để kiểm tra ngay mà không cần đợi sáng hôm sau: mở **Task Scheduler**, chuột phải vào task `Check ToDo AM` và chọn **Run**. Thông báo sẽ xuất hiện ngay ở góc phải màn hình.

## Roadmap

- [ ] Đóng gói cấu hình Task Scheduler thành script cài đặt tự động
- [ ] Hỗ trợ tùy chỉnh khung giờ nhắc nhở (không chỉ giới hạn buổi sáng)
- [ ] Thêm tuỳ chọn đồng bộ danh sách task từ nguồn ngoài (file, API)

## License

Phát hành theo giấy phép [MIT](LICENSE).
