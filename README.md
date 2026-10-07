# DevOps Panel

[![Tải bản cài](https://img.shields.io/badge/T%E1%BA%A3i%20b%E1%BA%A3n%20c%C3%A0i-Windows-2ea44f?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/NguyenCoDuoc/devops-panel/releases/latest/download/DevOpsPanel-Setup.exe)
[![Phiên bản mới nhất](https://img.shields.io/github/v/release/NguyenCoDuoc/devops-panel?style=for-the-badge&label=Phi%C3%AAn%20b%E1%BA%A3n)](https://github.com/NguyenCoDuoc/devops-panel/releases/latest)

DevOps Panel là ứng dụng Windows nhỏ để theo dõi và điều khiển môi trường phát triển chạy trên Windows và WSL. Ứng dụng dùng PowerShell và các thành phần có sẵn của Windows, không cần quyền quản trị viên khi cài cho tài khoản hiện tại.

## Tải về và cài đặt

1. Bấm nút **Tải bản cài** ở trên (tải `DevOpsPanel-Setup.exe` của bản mới nhất), hoặc vào trang [Releases](https://github.com/NguyenCoDuoc/devops-panel/releases/latest) để tải file `.rar` kèm hướng dẫn.
2. Chạy `DevOpsPanel-Setup.exe`. Nếu Windows hiện "Windows protected your PC" (file chưa ký số): bấm **More info** → **Run anyway**.
3. Panel được cài vào `%LOCALAPPDATA%\Programs\DevOpsPanel`, có shortcut ở Start Menu và Desktop. Nâng cấp: chạy bản cài mới, cấu hình được giữ nguyên.

## Chức năng

- **Dịch vụ:** bật / tắt Ubuntu trên WSL, PostgreSQL (Windows hoặc WSL), K3s trong WSL, Docker Desktop và Tailscale khi các thành phần tương ứng được cài.
- **Ứng dụng:** quét project .NET và Vite, chạy / dừng / khởi động lại nhiều app cùng lúc, trạng thái đang khởi động trên từng dòng, báo app sập và tự khởi động lại, bộ app (chạy theo thứ tự tool → backend → BFF → frontend), tìm kiếm, sắp xếp cột, cột CPU / RAM / phản hồi HTTP (tùy chọn), giải phóng port bị chiếm, xuất / nhập danh mục app cho team.
- **Git:** tất cả repo trong danh mục, fetch / pull nhiều repo, tạo nhánh theo git-flow (`feature/` `fix/` `bugfix/` từ `main`, `hotfix/` từ `production`), push và mở Merge Request đúng nhánh đích, cửa sổ Git kiểu Git Extensions (cây nhánh, graph commit, diff), màn hình Commit (stage / unstage, diff, commit).
- **Sức khỏe máy:** CPU, RAM, WSL, pin, mạng, tiến trình nặng nhất, cảnh báo ở khay hệ thống.
- **K3s:** node, pod, xem log, describe, khởi động lại pod, mở k9s.
- **Giao diện:** sáng / tối, icon outline, tab Trợ giúp (F1), chẩn đoán tốc độ cho máy chạy chậm.

> **Web Panel** (điều khiển từ điện thoại / máy khác qua Tailscale) thuộc **bản trả phí**, không có trong mã nguồn này. Liên hệ: coduoc2502@gmail.com

## Yêu cầu

- Windows 10/11 với Windows PowerShell 5.1 (có sẵn) và .NET Framework 4.8.
- WSL + Ubuntu, PostgreSQL, Docker Desktop, K3s, Tailscale, Git là tùy chọn: panel tự nhận những gì máy đang có.
- Để build launcher hoặc bộ cài: .NET Framework 4 compiler (`csc.exe`) có sẵn trên Windows.

## Chạy từ mã nguồn

Mở PowerShell tại thư mục dự án:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DevOpsPanel.ps1
```

Hoặc khởi chạy `DevOpsPanel.cmd`.

Để cài cho tài khoản Windows hiện tại từ mã nguồn (tạo launcher, shortcut và mục gỡ cài đặt):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Để build bộ cài phát hành:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-setup.ps1
```

File đầu ra là `dist\DevOpsPanel-Setup.exe`. Số phiên bản lấy từ `$PanelVersion` trong `DevOpsCore.ps1` (chỉ sửa ở đó); script build tự ghi vào launcher, bộ cài và mục gỡ cài đặt.

## Phát hành bản mới

1. Sửa `$PanelVersion` trong `DevOpsCore.ps1`, chạy `build-setup.ps1`.
2. Commit, tạo tag `vX.Y.Z` và push.
3. Tạo Release từ tag trên GitHub, đính kèm **`DevOpsPanel-Setup.exe`** (giữ đúng tên file này để nút **Tải bản cài** trong README luôn trỏ tới bản mới nhất) và file `.rar` kèm hướng dẫn.

## Cấu hình

Thiết lập người dùng được lưu ở `%APPDATA%\DevOpsPanel\config.json` và `%APPDATA%\DevOpsPanel\apps.json`. Tab **Cài đặt** cho phép đổi tên hiển thị, chọn giao diện sáng / tối, distro WSL, port PostgreSQL trong WSL và thư mục quét project. `pgUbuntuPort = 0` nghĩa là không theo dõi PostgreSQL trong WSL.

Danh mục `apps.json` gồm `scanRanges`, `apps`, `profiles` (bộ app) và `removed` (app đã gỡ khỏi panel). Mỗi app có thể khai báo `id`, `group`, `name`, `type`, `port`, `url`, `dir`, lệnh `start` và `autoRestart`. `type` thường là `backend`, `bff`, `frontend` hoặc `tool`; app `tool` không cần port.

## Cấu trúc chính

| Đường dẫn | Mục đích |
| --- | --- |
| `DevOpsPanel.ps1` | Giao diện desktop Windows Forms và điều phối tác vụ |
| `DevOpsCore.ps1` | Logic dùng chung: dò và điều khiển dịch vụ, K3s, app, Git, trạng thái hệ thống |
| `app/DevOpsApp.cs` | Mã nguồn launcher Windows |
| `installer/Setup.cs` | Mã nguồn bộ cài tự giải nén |
| `install.ps1`, `uninstall.ps1` | Cài hoặc gỡ ứng dụng cho user hiện tại |
| `build-setup.ps1` | Build bộ cài vào `dist` |
| `wsl/install-k9s.sh` | Cài/cập nhật k9s trong WSL và cấu hình kubeconfig K3s |

## Gỡ cài đặt

Settings → Apps → DevOps Panel → Uninstall (chọn giữ hoặc xoá cấu hình). Hoặc chạy `uninstall.ps1` trong thư mục cài đặt.

## Khắc phục sự cố

- **Không thấy Ubuntu:** kiểm tra `wsl --list --verbose` và chọn đúng distro trong tab Cài đặt.
- **Không điều khiển được PostgreSQL/K3s:** xác nhận service tồn tại trong distro và port PostgreSQL đã đặt đúng; thao tác start/stop dùng `systemctl` trong WSL.
- **App không xuất hiện:** thêm thư mục gốc trong Cài đặt, quét lại; với project không được nhận diện tự động, khai báo thủ công trong `apps.json`.
- **Chạy chậm / không load được Git:** tab Cài đặt → **Chẩn đoán tốc độ**, gửi kết quả cho người hỗ trợ.

## Hỗ trợ

coduoc2502@gmail.com

## Dữ liệu riêng tư

Không đưa lên GitHub các file `apps.json`, `settings.json`, log, binary đã build hoặc nội dung `dist`. Những file này có thể chứa đường dẫn dự án nội bộ, dữ liệu môi trường hoặc artifact phát hành. Dùng `.gitignore` trong repository để tránh thêm nhầm.
