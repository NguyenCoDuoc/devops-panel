# Prompt: sửa lỗi UI và thêm hai chế độ giao diện

Đóng vai Senior UI/UX Designer và Senior Frontend Engineer cho ứng dụng Windows desktop Develop Workspace. Dùng skill ui-ux-pro-max, đọc code và các ảnh lỗi hiện tại, rồi triển khai trực tiếp bằng PowerShell 5.1 + Windows Forms + .NET Framework. Giữ nguyên business logic, API và chức năng hiện có.

## Mục tiêu và trải nghiệm

- Đặt **Giao diện & màu sắc** trong tab **Cài đặt**, thành card riêng để ô tên, nút đổi tên và chọn chế độ không chen nhau.
- Giữ Light, Dark, Modern. Thêm đúng hai chế độ có ngôn ngữ thiết kế khác nhau: **Atelier** (giấy ấm, mực xanh, đồng; navbar tương phản, card nét kẻ và tiêu đề serif) và **Aurora** (xanh đêm, mint, xanh băng; navbar chuyển sắc, vùng chọn dạng pill, card bo mềm có đường sáng).
- Phân biệt bằng màu, hình dáng, đường viền, typography và cách đánh dấu mục được chọn ở cả navbar trên và sidebar. Không chỉ thay một màu accent hoặc sao chép template.
- Light/Dark/Modern vẫn có năm màu nhấn Indigo, Ocean, Teal, Violet, Graphite. Atelier/Aurora dùng phối màu riêng; hiển thị tên phối màu thay vì một lựa chọn accent gây hiểu nhầm.
- Áp dụng ngay, tự lưu, đọc lại khi mở app; giữ lựa chọn accent khi chuyển qua chế độ có phối màu riêng. Mặc định chỉ khôi phục accent Indigo. Lựa chọn dùng được bằng bàn phím, có nhãn và mô tả rõ; không dùng màu làm dấu hiệu duy nhất.
- Sửa các lỗi trong ảnh: ô chọn chế độ bị che; nút Thêm thư mục mất chữ; nút WSL disabled có chữ đen trên nền tối; tên nhánh/stat Git đè lên Xem thay đổi / Commit; mô tả DB bị cắt và header bảng màu đen. Ưu tiên sửa helper chung và nguyên nhân layout.

## Thiết kế và triển khai

- Đọc code đang chạy và tất cả caller của theme/config trước khi sửa. Bảo toàn các thay đổi đang có trong workspace.
- Tham khảo Fluent 2, IBM Design Language và các mẫu phù hợp trên Mobbin, Refero, Recent, Dribbble nếu truy cập được. Chắt lọc ý tưởng thành hướng riêng; không tuyên bố đã đọc nguồn không truy cập được.
- Tái sử dụng ThemePalettes, Set-Theme, Set-ControlTheme, helper icon và layout hiện tại. Dùng ui/Theme.ps1 làm nguồn token duy nhất, tránh để bảng màu trong PegasusPanel.ps1 ghi đè bảng màu chung.
- Phối đồng bộ background, surface, card, border, selection, hover, accent và link. Button, textbox, icon, navigation, bảng và control tạo mới đều sử dụng token hiện hành.
- Giữ riêng màu ngữ nghĩa thành công/cảnh báo/lỗi; không biến lỗi thành màu của theme. Không đổi business logic hoặc dữ liệu project.
- Kiểm tra tương phản chữ thường, chữ muted, link, navbar và chữ trên nút chính ở default/hover tối thiểu 4.5:1. Disabled vẫn đọc được và không tương tác. Icon trên nút chính dùng màu foreground của nút.
- Lưu thêm một trường colorScheme vào cấu hình người dùng hiện có. Cấu hình cũ thiếu trường hoặc giá trị không hợp lệ trở về Indigo; không làm mất trường cài đặt khác. Nếu lưu thất bại, giữ lựa chọn trước đó và báo lỗi có thể hiểu được.
- Bố cục Cài đặt và DB Helper thích ứng kích thước cửa sổ, cuộn khi thiếu chiều cao. Đo button sau khi có font, icon, padding; resize nhiều lần không được khiến button phình ra. Text dài chỉ ellipsis khi cần, có tooltip/accessible description đầy đủ; link thao tác luôn có vùng riêng.
- Giữ framework, không thêm dependency, không xây bộ chọn màu tùy ý hoặc theme editor ngoài yêu cầu.

## Kiểm chứng và bàn giao

- Kiểm tra cú pháp bằng Windows PowerShell 5.1.
- Có self-check cho cả năm chế độ, tương phản, fallback, lưu/đọc cấu hình, khôi phục mặc định, lỗi lưu và tên nhánh rất dài. Kiểm tra header của bảng được dựng trước khi handler owner-draw khởi tạo.
- Kiểm tra control và layout Cài đặt ở cửa sổ rộng/hẹp; render preview nếu khả dụng. Không start/stop dịch vụ, reset DB, thay đổi Git project hay ghi vào cấu hình thật chỉ để test.
- Chỉ báo cáo kiểm tra thực sự chạy; nêu phần DPI hoặc tương tác desktop chưa thể xác minh. Bàn giao file sửa, cách sử dụng và giới hạn còn lại.
