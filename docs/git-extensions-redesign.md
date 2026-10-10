# Git tab — Git Extensions workflow

Thiết kế dùng lại Git browser và cửa sổ Commit của ứng dụng, đưa bộ duyệt vào tab Git thay cho bố cục bảng repo chiếm nửa màn hình. Windows Forms và Git CLI hiện có vẫn là nền tảng; không thêm dependency.

Tham khảo tài liệu chính thức: [Browse repository](https://git-extensions-documentation.readthedocs.io/en/main/browse_repository.html) và [Commit](https://git-extensions-documentation.readthedocs.io/en/main/commit.html). Các phần được áp dụng là toolbar theo repository, cây ref bên trái, revision graph phía trên, chi tiết revision phía dưới và vùng stage/unstage riêng trong cửa sổ commit.

## Luồng đã triển khai

1. Chọn repository từ danh mục hoặc mở thư mục repo; tooltip hiển thị đường dẫn đầy đủ. Quét repo giữ lựa chọn hiện tại và các repo mở thêm trong phiên.
2. Cây Branches, Remotes, Tags và Submodules ở bên trái; nhánh hiện tại có dấu đánh dấu. Chọn ref để lọc lịch sử. Double-click nhánh hoặc menu Checkout yêu cầu xác nhận và dùng cơ chế chuyển nhánh hiện có.
3. Graph thể hiện quan hệ cha/con và merge, cùng nhãn branch/tag, tác giả, ngày, mã commit. Hai dòng Working directory và Commit index hiển thị số file chưa stage/đã stage của nhánh đang làm việc. Chúng không nối giả vào lịch sử ref được lọc.
4. Tìm commit theo message, tác giả, hash hoặc ref; Enter chuyển tới kết quả tiếp theo trong lịch sử đã tải. Có thể tải 300, 1000 hoặc 3000 commit.
5. Commit hiển thị metadata và message đầy đủ. Diff hiển thị file thay đổi và diff đúng revision, working tree hoặc index. File tree đọc nội dung snapshot được chọn, giới hạn preview 512 KB và báo file nhị phân. Console hiển thị trạng thái và kết quả tác vụ; Terminal mở PowerShell tại repo.
6. Cửa sổ Commit tách file chưa stage/đã stage. Double-click, Space/Enter hoặc nút Stage/Unstage chuyển file. Commit chỉ ghi phần đã stage; Ctrl+Enter tương đương nút Commit. Tác vụ ghi đang chạy chặn thao tác ghi trùng.
7. Fetch, pull fast-forward, tạo nhánh, Commit và Push + MR dùng repository đang mở. Chính sách git-flow/MR và bảo vệ nhánh của ứng dụng được giữ lại.

Các pane có splitter kéo điều chỉnh. Toolbar tự xuống hàng khi thiếu chiều ngang; các nút stage và commit cũng xuống hàng. Màu dùng năm theme chung của ứng dụng. Callback của host bị đóng hoặc request cũ không cập nhật repo/revision mới.

## Kiểm chứng

`powershell -NoProfile -ExecutionPolicy Bypass -File tests/Git.Tests.ps1`

Self-check dựng control Windows Forms thật, tạo repo tạm có nhánh/merge/tag/remote ref, file có khoảng trắng và một file có thay đổi ở cả index lẫn working tree. Kiểm tra graph, tìm kiếm, lọc nhánh không checkout, diff commit/working/index, file tree, đổi repo giữa callback đang chờ, giới hạn preview, stage và commit, chống thao tác trùng và giữ nguyên phần chưa stage. Kiểm tra toolbar ở 760/1400 px trong năm theme và cửa sổ Commit ở 760/1180 px; chạy kèm kiểm tra theme/contrast hiện có.

Thêm `-PreviewDirectory docs/git-previews` để xuất bitmap bố cục. RichTextBox của Windows Forms không hiển thị nội dung khi dùng DrawToBitmap; bitmap Diff chỉ dùng để xem bố cục, nội dung được assert trực tiếp trên control.

Chưa kiểm tra remote có xác thực, fetch/pull/push thật, DPI 125/150% hoặc bộ cài. Console là nhật ký tác vụ, không phải terminal tương tác. Submodules hiện là danh sách đường dẫn. Chưa triển khai GPG, stash/rebase/cherry-pick hoặc các lệnh chỉnh lịch sử ngoài phạm vi Git browser và thao tác hiện có.
