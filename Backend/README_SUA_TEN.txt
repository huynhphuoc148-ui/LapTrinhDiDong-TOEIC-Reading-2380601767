Bản sửa tên từ template TOEIC.zip người dùng cung cấp.
Đổi 2380600189 -> ToeicExam trong tên file/thư mục và nội dung text.
Giữ target net9.0 và phiên bản các package; chưa thêm chức năng thi TOEIC.
Giữ nguyên dữ liệu ảnh và mã chức năng template. Loại file metadata macOS.
Đã kiểm tra XML csproj, project references và solution references.
Chưa restore/build/chạy vì môi trường soạn không có .NET SDK.
Cần .NET 9 SDK trên máy chạy. Không tự đổi net9.0 thành net8.0.
Giải nén, đặt Backend cạnh thư mục Flutter kiemtragk.
Trong terminal ở Backend:
  dotnet --list-sdks
  dotnet restore ToeicExam.sln
  dotnet build ToeicExam.sln --no-restore
Chưa chạy migration: cần cấu hình SQL instance/database và kiểm tra migration trước.
Các bảng toeic đã tạo không thay phần identity Abp của template.
