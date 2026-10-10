# Develop Workspace

[![Tải bản cài](https://img.shields.io/badge/T%E1%BA%A3i%20b%E1%BA%A3n%20c%C3%A0i-Windows-2ea44f?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/NguyenCoDuoc/devops-panel/releases/latest/download/PegasusPanel-Setup.exe)
[![Phiên bản mới nhất](https://img.shields.io/github/v/release/NguyenCoDuoc/devops-panel?style=for-the-badge&label=Phi%C3%AAn%20b%E1%BA%A3n)](https://github.com/NguyenCoDuoc/devops-panel/releases/latest)

Develop Workspace là ứng dụng Windows nhỏ để theo dõi và điều khiển môi trường phát triển chạy trên Windows và WSL. Ứng dụng dùng PowerShell và các thành phần có sẵn của Windows, không cần quyền quản trị viên khi cài cho tài khoản hiện tại.

## Tải về và cài đặt

1. Bấm nút **Tải bản cài** ở trên (tải `PegasusPanel-Setup.exe` của bản mới nhất), hoặc vào trang [Releases](https://github.com/NguyenCoDuoc/devops-panel/releases/latest) để tải file `.rar` kèm hướng dẫn.
2. Chạy `PegasusPanel-Setup.exe`. Nếu Windows hiện "Windows protected your PC" (file chưa ký số): bấm **More info** → **Run anyway**.
3. Panel được cài vào `%LOCALAPPDATA%\Programs\PegasusPanel`, có shortcut ở Start Menu và Desktop. Nâng cấp: chạy bản cài mới, cấu hình được giữ nguyên.

## Chức năng

- **Dịch vụ:** bật / tắt Ubuntu trên WSL, PostgreSQL (Windows hoặc WSL), K3s trong WSL, Docker Desktop và Tailscale khi các thành phần tương ứng được cài.
- **Ứng dụng:** quét project .NET và Vite, chạy / dừng / khởi động lại nhiều app cùng lúc, trạng thái đang khởi động trên từng dòng, báo app sập và tự khởi động lại, bộ app (chạy theo thứ tự tool → backend → BFF → frontend), tìm kiếm, sắp xếp cột, cột CPU / RAM / phản hồi HTTP (tùy chọn), giải phóng port bị chiếm, **public port ra Internet qua Dev Tunnels** (chuột phải app đang chạy → *Public ra Internet*, giống Forward Port của VS Code; cần `devtunnel` CLI, panel gợi ý cài bằng winget và đăng nhập GitHub/Microsoft lần đầu; link tự copy, thoát panel tự dừng), xuất / nhập danh mục app cho team.
- **Git:** chọn hoặc mở repository ngay trong tab, cây Branches/Remotes/Tags/Submodules, graph commit và nhãn ref, Working directory/Commit index, các tab Commit/Diff/File tree/Console. Fetch, pull fast-forward, commit, tạo nhánh theo git-flow và Push + MR thao tác trên repo đang mở. Chọn nhánh để xem lịch sử; double-click để checkout có xác nhận. Cửa sổ Commit tách file chưa stage/đã stage, xem diff, stage/unstage và commit.
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
powershell -NoProfile -ExecutionPolicy Bypass -File .\PegasusPanel.ps1
```

Hoặc khởi chạy `PegasusPanel.cmd`.

Để cài cho tài khoản Windows hiện tại từ mã nguồn (tạo launcher, shortcut và mục gỡ cài đặt):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Để build bộ cài phát hành:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-setup.ps1
```

File đầu ra là `dist\PegasusPanel-Setup.exe`. Số phiên bản lấy từ `$PanelVersion` trong `PegasusCore.ps1` (chỉ sửa ở đó); script build tự ghi vào launcher, bộ cài và mục gỡ cài đặt.

## Phát hành bản mới

1. Sửa `$PanelVersion` trong `PegasusCore.ps1`, chạy `build-setup.ps1`.
2. Commit, tạo tag `vX.Y.Z` và push.
3. Tạo Release từ tag trên GitHub, đính kèm **`PegasusPanel-Setup.exe`** (giữ đúng tên file này để nút **Tải bản cài** trong README luôn trỏ tới bản mới nhất) và file `.rar` kèm hướng dẫn.

## Cấu hình

Thiết lập người dùng được lưu ở `%APPDATA%\PegasusPanel\config.json` và `%APPDATA%\PegasusPanel\apps.json`. Tab **Cài đặt** cho phép đổi tên hiển thị, chọn giao diện, distro WSL, port PostgreSQL trong WSL và thư mục quét project. `pgUbuntuPort = 0` nghĩa là không theo dõi PostgreSQL trong WSL.

Trong **Cài đặt → Giao diện & màu sắc**, chọn **Light, Dark, Modern, Atelier hoặc Aurora**. Atelier dùng nền giấy ấm, navbar xanh mực và card nét đồng với tiêu đề serif; Aurora dùng nền xanh đêm, mint, navbar chuyển sắc và card bo mềm. Hai chế độ này có phối màu riêng. Modern dùng nền sáng dịu, navbar chuyển sắc theo màu nhấn và card bo 12px có bóng mềm. Light/Dark/Modern cho phép chọn màu nhấn **Indigo, Ocean, Teal, Violet hoặc Graphite**; lựa chọn được giữ lại khi chuyển sang Atelier/Aurora rồi quay về. Thay đổi áp dụng ngay và tự lưu. Nút **Mặc định** khôi phục Indigo, giữ các cài đặt khác. Cấu hình cũ hoặc màu nhấn không hợp lệ tự dùng Indigo.

Kiểm tra UI độc lập (không gọi dịch vụ hoặc dùng cấu hình thật): `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Theme.Tests.ps1`. Thêm `-PreviewDirectory docs/theme-previews` để render các control Cài đặt, DB Helper và trường hợp text dài của từng chế độ.

Kiểm tra tab Git và stage/commit trên repository tạm: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Git.Tests.ps1`. Kiểm tra này không gọi remote hoặc thay đổi repo dự án. Luồng và phạm vi triển khai được ghi tại [docs/git-extensions-redesign.md](docs/git-extensions-redesign.md).

Danh mục `apps.json` gồm `scanRanges`, `apps`, `profiles` (bộ app) và `removed` (app đã gỡ khỏi panel). Mỗi app có thể khai báo `id`, `group`, `name`, `type`, `port`, `url`, `dir`, lệnh `start` và `autoRestart`. `type` thường là `backend`, `bff`, `frontend` hoặc `tool`; app `tool` không cần port.

## Cấu trúc chính

| Đường dẫn | Mục đích |
| --- | --- |
| `PegasusPanel.ps1` | Giao diện desktop Windows Forms và điều phối tác vụ |
| `PegasusCore.ps1` | Logic dùng chung: dò và điều khiển dịch vụ, K3s, app, Git, trạng thái hệ thống |
| `app/PegasusApp.cs` | Mã nguồn launcher Windows |
| `installer/Setup.cs` | Mã nguồn bộ cài tự giải nén |
| `install.ps1`, `uninstall.ps1` | Cài hoặc gỡ ứng dụng cho user hiện tại |
| `build-setup.ps1` | Build bộ cài vào `dist` |
| `wsl/install-k9s.sh` | Cài/cập nhật k9s trong WSL và cấu hình kubeconfig K3s |

## Gỡ cài đặt

Settings → Apps → Develop Workspace → Uninstall (chọn giữ hoặc xoá cấu hình). Hoặc chạy `uninstall.ps1` trong thư mục cài đặt.

## Khắc phục sự cố

- **Không thấy Ubuntu:** kiểm tra `wsl --list --verbose` và chọn đúng distro trong tab Cài đặt.
- **Không điều khiển được PostgreSQL/K3s:** xác nhận service tồn tại trong distro và port PostgreSQL đã đặt đúng; thao tác start/stop dùng `systemctl` trong WSL.
- **App không xuất hiện:** thêm thư mục gốc trong Cài đặt, quét lại; với project không được nhận diện tự động, khai báo thủ công trong `apps.json`.
- **Chạy chậm / không load được Git:** tab Cài đặt → **Chẩn đoán tốc độ**, gửi kết quả cho người hỗ trợ.

## Hỗ trợ

coduoc2502@gmail.com

## Dữ liệu riêng tư

Không đưa lên GitHub các file `apps.json`, `settings.json`, log, binary đã build hoặc nội dung `dist`. Những file này có thể chứa đường dẫn dự án nội bộ, dữ liệu môi trường hoặc artifact phát hành. Dùng `.gitignore` trong repository để tránh thêm nhầm.
