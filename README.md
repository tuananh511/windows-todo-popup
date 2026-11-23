# Windows ToDo Popup

[![CI](https://github.com/tuananh511/windows-todo-popup/actions/workflows/ci.yml/badge.svg)](https://github.com/tuananh511/windows-todo-popup/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tuananh511/windows-todo-popup)](https://github.com/tuananh511/windows-todo-popup/releases/latest)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE)

Mỗi sáng, một popup nhỏ gọn nhắc bạn **những việc Microsoft To Do đến hạn hôm nay hoặc đã quá hạn**. Tick hoàn thành ngay trong popup, hoặc bấm "Nhắc lại sau 60 phút".

Không có chương trình chạy ngầm, không tốn RAM; Windows chỉ gọi nó khi bạn mở máy.

<!-- Thêm ảnh chụp: chạy `check_todo.ps1 -Demo`, chụp popup, lưu vào docs/popup.png rồi bỏ dấu chú thích ở dòng dưới -->
<!-- ![Popup nhắc việc](docs/popup.png) -->

---

## Cài đặt (3 bước, không cần kiến thức kỹ thuật)

1. Vào trang **[Releases](https://github.com/tuananh511/windows-todo-popup/releases/latest)**, tải file **`WindowsTodoPopup.zip`**, rồi **chuột phải > Extract All** để giải nén.
2. Mở thư mục vừa giải nén, **bấm đúp `Cai-dat.bat`**.
3. Làm theo hướng dẫn trên màn hình: bấm **OK**, rồi khi trình duyệt mở ra thì **đăng nhập tài khoản Microsoft** bạn dùng cho To Do và bấm **Accept**.

Xong! Popup thử sẽ hiện ra ngay. Từ mai, mỗi lần mở máy (và lúc 07:30 nếu máy đang bật), popup sẽ tự hiện nếu bạn có việc đến hạn.

> **Windows hiện cảnh báo xanh "Windows protected your PC"?** Đây là cảnh báo chung với mọi file tải từ Internet chưa có chữ ký số. Bấm **More info**, rồi **Run anyway**. Toàn bộ mã nguồn nằm ngay trong repo này để bạn kiểm tra.
>
> **Phải giải nén trước!** Nếu chạy `Cai-dat.bat` từ bên trong file zip, bạn sẽ thấy thông báo thiếu file. Hãy giải nén (Extract All) rồi chạy lại.

Chương trình **không cần quyền admin** và được cài vào `%LOCALAPPDATA%\WindowsTodoPopup`.

## Dùng hằng ngày

| Bạn muốn | Làm thế nào |
|---|---|
| Xem việc hôm nay ngay lập tức | Bấm shortcut **Nhắc việc - Chạy ngay** ngoài Desktop (hoặc trong Start Menu) |
| Đánh dấu một việc đã xong | Tick vào ô vuông trước tên việc (bỏ tick để hoàn tác) |
| Bị nhắc lại sau ít phút | Bấm **Nhắc lại sau 60 phút** ở cuối popup |
| Mở ứng dụng To Do | Bấm **Mở To Do** |
| Đóng popup | Bấm **Đã xem**, dấu **✕**, hoặc phím `Esc` |
| Đổi giờ, màu sắc, ẩn bớt danh sách | Start Menu > **Windows ToDo Popup** > **Cài đặt (mở config.json)** |
| Đăng nhập lại (đổi tài khoản, hết hạn) | Start Menu > **Windows ToDo Popup** > **Đăng nhập lại Microsoft** |
| Gỡ cài đặt | **Settings > Apps > Installed apps > Windows ToDo Popup > Uninstall**, hoặc bấm đúp `Go-cai-dat.bat` |

Popup chỉ hiện các việc **có đặt hạn (due date)** là hôm nay hoặc đã qua. Việc không có hạn hoặc hạn ở tương lai sẽ không hiện. Nếu hôm nay không có việc nào, popup tự động không hiện (trừ khi bạn bấm "Chạy ngay").

## Cấu hình (`config.json`)

Mở bằng Notepad, sửa rồi lưu lại. Lần chạy kế tiếp sẽ áp dụng.

| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `RunUntilHour` | `12` | Chỉ tự hiện popup **trước** giờ này (0 đến 24). Đặt `24` để hiện cả ngày (ví dụ mở máy lúc 14h vẫn được nhắc). |
| `ShowOverdue` | `true` | `false` thì chỉ hiện việc đến hạn hôm nay, không hiện việc quá hạn. |
| `ExcludeLists` | `[]` | Tên các danh sách không muốn nhắc, ví dụ `["Mua sắm", "Đọc sách"]`. |
| `SnoozeMinutes` | `60` | Số phút của nút "Nhắc lại sau". |
| `AccentColor` | `#0078D4` | Màu nhấn (mã HTML). |
| `OverdueColor` | `#C45A4E` | Màu mục "Quá hạn". |
| `InkColor` | `#111114` | Màu chữ chính và nút chính. |

Lưu ý: file là JSON nên không được có chú thích và các giá trị chữ phải nằm trong dấu nháy kép `"`. Nếu sửa sai, chương trình tự dùng giá trị mặc định.

## Câu hỏi thường gặp

**Popup không hiện?**
Kiểm tra theo thứ tự: (1) hôm nay bạn có việc nào *có đặt hạn* là hôm nay/quá hạn không? (2) bạn mở máy sau giờ `RunUntilHour` (mặc định 12h)? (3) hôm nay popup đã hiện một lần rồi? Cách nhanh nhất để kiểm tra: bấm **Nhắc việc - Chạy ngay**. Nếu vẫn lỗi, mở file nhật ký `%LOCALAPPDATA%\WindowsTodoPopup\debug.log`.

**Trình duyệt tự mở ra bắt đăng nhập lúc mở máy?**
Phiên đăng nhập đã hết hạn nên chương trình tự đăng nhập lại. Hãy đăng nhập là xong.

**Tài khoản cơ quan/trường học báo cần quản trị viên cấp quyền?**
Một số tổ chức chặn ứng dụng bên ngoài. Hãy nhờ quản trị viên IT cho phép quyền `Tasks.ReadWrite` của ứng dụng "Microsoft Graph Command Line Tools", hoặc dùng tài khoản Microsoft cá nhân.

**Dữ liệu của tôi có bị gửi đi đâu không?**
Không. Chương trình chỉ nói chuyện trực tiếp với Microsoft Graph (máy chủ Microsoft) bằng tài khoản của bạn, để đọc danh sách việc và đánh dấu hoàn thành khi bạn tick. Không có máy chủ trung gian nào, không có thống kê hay theo dõi. Mã nguồn công khai để bạn tự kiểm tra.

**Cần thu hồi quyền đã cấp?**
Tài khoản cá nhân: vào <https://account.live.com/consent/Manage>. Tài khoản cơ quan/trường: vào <https://myaccount.microsoft.com> > *Ứng dụng của tôi* (My apps). Tìm "Microsoft Graph Command Line Tools" rồi chọn thu hồi.

**Cài đè phiên bản mới có mất cấu hình không?**
Không. `config.json` cũ được giữ nguyên.

---

## Dành cho nhà phát triển

### Chạy trực tiếp từ mã nguồn

```powershell
# Xem thử giao diện với dữ liệu mẫu (không cần đăng nhập, không gọi mạng)
powershell -ExecutionPolicy Bypass -File .\check_todo.ps1 -Demo

# Chạy thật, bỏ qua giới hạn giờ và "1 lần mỗi ngày"
powershell -ExecutionPolicy Bypass -File .\check_todo.ps1 -Force
```

| Tham số | Tác dụng |
|---|---|
| `-Force` | Bỏ qua khung giờ và giới hạn mỗi ngày; luôn hiện popup (kể cả khi không có việc). |
| `-Demo` | Dữ liệu mẫu, không đăng nhập. Hợp để chụp ảnh. |
| `-Login` | Chỉ đăng nhập Microsoft rồi thoát. |
| `-Snoozed` | Dùng nội bộ cho lịch "Nhắc lại sau". |

### Cấu trúc

```
Cai-dat.bat / install.ps1      Cài đặt một chạm (người dùng bấm đúp Cai-dat.bat)
Go-cai-dat.bat / uninstall.ps1 Gỡ cài đặt
check_todo.ps1                 Chương trình chính (lấy task + popup)
config.json                    Cấu hình mặc định
VERSION                        Số phiên bản (phải khớp tag khi phát hành)
.github/workflows/ci.yml       Kiểm tra cú pháp 5.1, BOM, PSScriptAnalyzer
.github/workflows/release.yml  Gắn tag vX.Y.Z là tự tạo Release + WindowsTodoPopup.zip
```

### Quy tắc bắt buộc về encoding

- Mọi file `.ps1` phải lưu **UTF-8 with BOM**. Windows PowerShell 5.1 đọc file không có BOM theo bảng mã ANSI nên tiếng Việt sẽ bị vỡ. CI sẽ báo đỏ nếu thiếu BOM. (VS Code: góc dưới bên phải > *Save with Encoding* > *UTF-8 with BOM*.)
- Mọi file `.bat` chỉ được chứa **ký tự ASCII**.
- `.gitattributes` ép `.ps1`/`.bat`/`.json` dùng CRLF khi checkout.
- Code phải chạy được trên **Windows PowerShell 5.1** (không dùng `??`, `?.`, toán tử ba ngôi, `&&`).

### Phát hành phiên bản mới

```powershell
# 1) Sửa VERSION và CHANGELOG.md, commit
# 2) Gắn tag trùng với VERSION rồi đẩy lên
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions sẽ kiểm tra tag khớp `VERSION`, đóng gói và tạo Release kèm `WindowsTodoPopup.zip`. Đường dẫn tải ổn định: `https://github.com/tuananh511/windows-todo-popup/releases/latest/download/WindowsTodoPopup.zip`.

### Lộ trình

- [x] Cài đặt một chạm, gỡ cài đặt, mục trong Settings > Apps
- [x] Shortcut "Chạy ngay" (`-Force`)
- [x] Tick hoàn thành, nhắc lại sau N phút
- [x] `config.json` (khung giờ, danh sách loại trừ, màu sắc)
- [x] CI + Release tự động
- [ ] Cửa sổ Cài đặt bằng giao diện (thay cho mở `config.json`)
- [ ] Nguồn việc khác: Todoist (Outlook Tasks thực chất đã là Microsoft To Do nên script đã đọc được)
- [ ] Nhắc khi mở khóa máy (Workstation unlock)
- [ ] Hỗ trợ màn hình DPI cao (cần thử nghiệm layout)

## Giấy phép

Xem file [LICENSE](LICENSE).
