# DevOps Panel

DevOps Panel là ứng dụng Windows nhỏ để theo dõi và điều khiển môi trường phát triển chạy trên Windows và WSL. Ứng dụng dùng PowerShell và các thành phần có sẵn của Windows, không cần quyền quản trị viên khi cài cho tài khoản hiện tại.

## Chức năng

- Quản lý trạng thái Ubuntu trên WSL, PostgreSQL chạy trên Windows hoặc WSL, K3s trong WSL, Docker Desktop và Tailscale khi các thành phần tương ứng được cài.
- Xem thông tin sức khỏe máy, tài nguyên và các tiến trình dùng nhiều RAM.
- Theo dõi node, pod K3s; xem log và khởi động lại pod.
- Tìm các ứng dụng phát triển đang nghe trên những dải port đã cấu hình, rồi chạy, dừng hoặc mở chúng.
- Quét project .NET và Vite từ các thư mục đã chọn để tạo danh mục ứng dụng ban đầu.
- Tùy chọn mở Web Panel qua Tailscale. Web server chỉ lắng nghe trên `127.0.0.1:8787`; Tailscale Serve cung cấp truy cập từ tailnet và danh sách tài khoản cho phép nằm trong `webpanel.json`.

## Yêu cầu

- Windows 10/11 với Windows PowerShell 5.1 và WSL đã bật.
- Một bản phân phối Linux trên WSL (Ubuntu được tự chọn nếu có).
- Các dịch vụ muốn quản lý phải được cài riêng. Ví dụ: PostgreSQL, K3s trong WSL, Docker Desktop hoặc Tailscale.
- Để build launcher hoặc bộ cài: .NET Framework 4 compiler (`csc.exe`) và Windows PowerShell có sẵn trên Windows.
- Web Panel cần Tailscale nếu muốn truy cập từ thiết bị khác; truy cập tại máy vẫn dùng được qua localhost.

## Chạy từ mã nguồn

Mở PowerShell tại thư mục dự án:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DevOpsPanel.ps1
```

Hoặc khởi chạy `DevOpsPanel.cmd` nếu có trong bản checkout. Có thể chạy launcher đã build `DevOpsPanel.exe` hoặc `DUOCNC DevOps.exe` nếu các file đó có trong bản phát hành.

Để cài cho tài khoản Windows hiện tại, tạo launcher, shortcut và mục gỡ cài đặt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Để build bộ cài phát hành:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-setup.ps1
```

File đầu ra là `dist\DevOpsPanel-Setup.exe`. Bộ cài chỉ đóng gói payload cần thiết; Web Panel và cấu hình máy cá nhân không được đóng gói.

## Cấu hình

Thiết lập người dùng được lưu ở `%APPDATA%\DevOpsPanel\config.json` và `%APPDATA%\DevOpsPanel\apps.json`. Tab **Cài đặt** cho phép chọn distro WSL, port PostgreSQL trong WSL, tự khởi động Ubuntu và thư mục quét project. `pgUbuntuPort = 0` nghĩa là không theo dõi PostgreSQL trong WSL.

Danh mục `apps.json` gồm `scanRanges` và `apps`. Mỗi app có thể khai báo `id`, `group`, `name`, `type`, `port`, `url`, `dir` và lệnh `start`. `type` thường là `backend`, `bff`, `frontend` hoặc `tool`; app `tool` không cần port. Danh mục tại thư mục nguồn có thể chứa đường dẫn và cấu hình riêng của máy; hãy tạo danh mục riêng trên máy sử dụng, đừng commit dữ liệu cá nhân.

Web Panel chạy trên cổng `8787`. Tệp `webpanel.json` cạnh script có thể ghi đè danh sách Tailscale login được phép:

```json
{
  "allowedLogins": ["you@example.com"]
}
```

Chỉ bật truy cập từ tailnet sau khi kiểm tra danh sách cho phép. Không chuyển tiếp cổng này trực tiếp ra Internet.

## Cấu trúc chính

| Đường dẫn | Mục đích |
| --- | --- |
| `DevOpsPanel.ps1` | Giao diện desktop Windows Forms và điều phối tác vụ |
| `DevOpsCore.ps1` | Logic dùng chung để dò và điều khiển dịch vụ, K3s, app và trạng thái hệ thống |
| `WebPanel.ps1`, `webpanel.html` | HTTP API cục bộ và giao diện Web Panel tùy chọn |
| `app/DevOpsApp.cs` | Mã nguồn launcher Windows |
| `installer/Setup.cs` | Mã nguồn bộ cài tự giải nén |
| `install.ps1`, `uninstall.ps1` | Cài hoặc gỡ ứng dụng cho user hiện tại |
| `build-setup.ps1` | Build bộ cài vào `dist` |
| `wsl/install-k9s.sh` | Cài/cập nhật k9s trong WSL và cấu hình kubeconfig K3s |

## Gỡ cài đặt

Chạy `uninstall.ps1` trong thư mục cài đặt. Script xóa launcher, shortcut và mục đăng ký ứng dụng; giữ nguyên script và môi trường WSL/dịch vụ của bạn.

## Khắc phục sự cố

- **Không thấy Ubuntu:** kiểm tra `wsl --list --verbose` và chọn đúng distro trong tab Cài đặt.
- **Không điều khiển được PostgreSQL/K3s:** xác nhận service tồn tại trong distro và port PostgreSQL đã đặt đúng; thao tác start/stop dùng `systemctl` trong WSL.
- **App không xuất hiện:** thêm thư mục gốc trong Cài đặt, quét lại; với project không được nhận diện tự động, khai báo thủ công trong danh mục `apps.json`.
- **Không vào được Web Panel:** kiểm tra `webpanel.log`, xác nhận Tailscale đang chạy, `tailscale serve` trỏ tới cổng cục bộ 8787 và login nằm trong `allowedLogins`.

## Dữ liệu riêng tư

Không đưa lên GitHub các file `apps.json`, `settings.json`, `webpanel.json`, log, binary đã build hoặc nội dung `dist`. Những file này có thể chứa đường dẫn dự án nội bộ, tài khoản được phép, dữ liệu môi trường hoặc artifact phát hành. Dùng `.gitignore` trong repository để tránh thêm nhầm.
