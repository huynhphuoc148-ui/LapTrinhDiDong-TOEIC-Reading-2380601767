# Bản nối API thật — TOEIC Classroom

Được bổ sung trực tiếp từ `kiemtragk.zip` bạn gửi. Đây là mốc triển khai tiếp theo, chưa phải toàn bộ bài giữa kỳ hoàn chỉnh.

## Phần đã bổ sung trong mã

- Web giảng viên tại `/toeic/index.html`: đăng nhập ABP, nhập JSON 100 câu, xem trước, lưu nháp, xuất bản, mở ca sáng/chiều/tối với danh sách tài khoản, xem thống kê và công bố điểm.
- API `/api/toeic`: dùng SQL Server với schema `toeic` đã chuẩn bị. Không tạo một database/schema nghiệp vụ khác.
- Flutter: đăng nhập thật, lịch thi được phân công, bắt đầu/tiếp tục bài, chọn/đổi/bỏ đáp án, đánh dấu xem lại, lưu server, đồng hồ, nộp và xem điểm theo giờ công bố.
- Cho phép nộp khi trả lời 0, 1 hoặc bất kỳ số câu nào. Câu không chọn tính vào `SkippedCount`, tách biệt câu chọn sai.
- Xáo trộn nguyên nhóm trong từng Part, giữ nhóm khóa ở vị trí cũ; không xáo các câu trong một nhóm. Đảo lựa chọn theo cờ từng câu, lưu thứ tự cố định trong bài làm.
- API chỉ trả câu hỏi/lựa chọn/bài đọc khi đang thi, không trả khóa đáp án/gợi ý/giải thích. Chấm theo ChoiceId gốc nên việc đảo A/B/C/D không làm sai điểm.
- Server kiểm tra danh sách dự thi và hạn vào thi. Hạn nộp = min(giờ bắt đầu làm + 75 phút, giờ kết thúc ca).
- Tác vụ mỗi 15 giây tìm bài quá hạn và chấm/nộp. Khi đọc lại bài quá hạn, API cũng tự hoàn tất. Server cần đang chạy; nếu tắt rồi bật, lượt quét sau xử lý các bài quá hạn.
- Quyền `Pages.Toeic.Manage` cho giảng viên. Tạo role Host `Student` không có quyền quản lý; Admin không còn là role mặc định của tài khoản mới.
- Mã giao diện minh họa cũ `lib/classroom_app.dart` giữ nguyên. `main.dart` chuyển sang app sinh viên nối API.

## 1. Áp dụng bản cập nhật

Dừng `flutter run` và backend đang chạy (Ctrl+C trong từng terminal).
Đặt file `CapNhat_TOEIC.ps1` trong thư mục dự án có `pubspec.yaml` và `Backend`.
Mở PowerShell tại thư mục:

```powershell
cd "D:\BT\DIDONG\B5\Kiemtra\kiemtragk"
powershell -NoProfile -ExecutionPolicy Bypass -File .\CapNhat_TOEIC.ps1 -ProjectRoot .
```

Script chỉ ghi các file liệt kê sẵn; có kiểm tra mã hiện tại còn khớp bản ZIP và sao lưu trước khi ghi. Nếu một file đã được sửa sau khi gửi ZIP, script dừng trước khi thay đổi; gửi lại thông báo để ghép mã, không xóa sửa đổi của bạn.

Script tự đổi riêng giá trị Database/Initial Catalog trong hai connection string của Migrator và Web.Mvc sang `ToeicExamDesignDb`. Không đổi server hoặc cách xác thực. Nếu database bạn đã tạo có tên khác, truyền `-DatabaseName TenDatabaseThucTe` và dùng đúng database đó khi kiểm tra schema SQL.

Sao lưu tại `TOEIC_backup_YYYYMMDD_HHMMSS`. Bản sao chứa cả cấu hình riêng của máy bạn, chỉ giữ trên máy; không gửi công khai. Nếu cần quay lại, dừng server/app rồi chạy `Restore.ps1` trong thư mục sao lưu. Restore kiểm tra bạn chưa sửa tiếp file sau khi cài, tránh ghi đè công việc mới.

## 2. Kiểm tra database, không xóa dữ liệu

Mở SSMS, chọn database `ToeicExamDesignDb`, chạy:

```sql
SELECT DB_NAME() AS CurrentDatabase;
SELECT SCHEMA_NAME(schema_id) AS SchemaName, name
FROM sys.tables WHERE schema_id=SCHEMA_ID(N'toeic');
SELECT name FROM sys.procedures WHERE schema_id=SCHEMA_ID(N'toeic');
```

Cần có 18 bảng `toeic` và các procedure `PublishVersion`, `SaveResponse`, `SubmitAttempt`.
Nếu đã có đủ thì không cần chạy lại script tạo schema.
Nếu chưa có, mở toàn bộ `Database/TOEIC_ALL_IN_ONE.sql` trong SSMS và Execute toàn bộ. Script này dùng tên `ToeicExamDesignDb`; nếu dùng tên khác, chỉnh đúng tên ở đầu script trước khi chạy. Không chọn một đoạn ở giữa.

Kiểm tra hai file:

- `Backend/src/ToeicExam.Migrator/appsettings.json`
- `Backend/src/ToeicExam.Web.Mvc/appsettings.json`

Kết nối mặc định cho SQL Server local default instance/Windows Authentication:

```json
"Default": "Server=localhost;Database=ToeicExamDesignDb;Trusted_Connection=True;TrustServerCertificate=True;"
```

Chỉ dùng `localhost` nếu SSMS của bạn kết nối default instance local. Nếu SSMS dùng `TENMAY\\SQLEXPRESS`, điền đúng instance trong JSON với hai dấu `\\`. Giữ nguyên phần cấu hình còn lại. Trong phát triển local, TrustServerCertificate giúp dùng chứng chỉ local.

Không cần cấu hình Web.Host cho mốc này. Chạy Web.Mvc, vì API mới nằm trong dự án đó.

## 3. Build, seed tài khoản/quyền rồi chạy backend

Terminal 1:

```powershell
cd "D:\BT\DIDONG\B5\Kiemtra\kiemtragk\Backend"
dotnet restore ToeicExam.sln
dotnet build ToeicExam.sln
dotnet test .\test\ToeicExam.Web.Tests\ToeicExam.Web.Tests.csproj --filter FullyQualifiedName~ToeicValidationTests
```

Nếu build báo error, dừng tại đây và gửi toàn bộ lỗi đầu tiên; không tiếp tục chạy một bản build cũ.
Sau khi build thành công:

```powershell
dotnet run --project .\src\ToeicExam.Migrator\ToeicExam.Migrator.csproj
```

Đọc database mà Migrator in ra, phải đúng `ToeicExamDesignDb`, rồi trả lời `Y` và Enter khi được hỏi. Bước này tạo/cập nhật bảng ABP và seed thêm quyền/role mới. Không drop database, không xóa bảng `toeic`. Chạy lại Migrator ngay cả khi đã chạy trước bản cập nhật để bổ sung quyền mới.

Nếu chưa làm bước tải tài nguyên web ABP:

```powershell
cd .\src\ToeicExam.Web.Mvc
npm install
npx gulp build
cd ..\..
```

Từ thư mục Backend, chạy:

```powershell
dotnet run --project .\src\ToeicExam.Web.Mvc\ToeicExam.Web.Mvc.csproj --launch-profile Toeic.Local
```

Giữ terminal chạy. Địa chỉ local của profile này: `http://localhost:5000`.
Mở `http://localhost:5000/toeic/index.html`.
Nếu dùng seed mặc định lần đầu, admin là `admin`, mật khẩu `123qwe`; nếu đã đổi thì dùng mật khẩu bạn đã đổi. Đổi mật khẩu mặc định trong trang quản lý tài khoản sau khi vào được.

Mốc này chỉ dùng Host (không tenant). Trong trang login ABP ở `/Account/Login`, chọn Host/để trống tenancy name. App và web quản lý TOEIC mới đăng nhập Host bằng token.

Nếu 403 “không có quyền quản lý TOEIC”: kiểm tra đã chạy lại Migrator; khởi động lại backend và đăng nhập lại. Role Admin Host phải có quyền `Pages.Toeic.Manage`.

## 4. Tạo tài khoản sinh viên

Vào `http://localhost:5000/Users` bằng tài khoản admin Host. Nếu chưa đăng nhập cookie của trang ABP, trang này yêu cầu đăng nhập riêng; web TOEIC dùng token nên không tự đăng nhập cookie ABP.

Tạo ví dụ `sv01`, `sv02` với email khác nhau và mật khẩu theo yêu cầu trên form.
Chỉ chọn role `Student / Sinh viên`, bỏ chọn Admin. Bật Active. Đừng dùng tài khoản Tenant Default cho module này.
Sau đó trở lại `/toeic/index.html`, bấm Tải lại dữ liệu để danh sách có sinh viên vừa tạo.

## 5. Chạy thử một ca thi hoàn chỉnh

1. Web giảng viên: bấm “Nạp mẫu kiểm thử 100 câu”. Đây là đề kỹ thuật tự tạo, không phải nội dung Reading v10 hay đáp án đề gốc.
2. Bấm “Xem trước”, xem nội dung. Bấm “Kiểm tra và lưu bản nháp”.
3. Trong danh sách đề, bấm “Xuất bản”. Nếu đề thiếu câu/đáp án/bài đọc, server từ chối.
4. Tạo ca, chọn đề vừa xuất bản, chọn `sv01` và `sv02`. Nhập bắt đầu trước hiện tại khoảng 1 phút, hạn vào sau 30 phút, kết thúc sau 90 phút để thử ngay. Chọn ca sáng/chiều/tối theo bài của bạn.
5. Điền giờ công bố điểm bằng hiện tại để xem kết quả ngay khi nộp; hoặc để trống và thử nút “Công bố điểm ngay” sau đó.
6. Bấm tạo và mở lịch. Việc tạo lịch tương lai không cho phép sinh viên vào trước giờ: server sẽ kiểm tra.
7. App đăng nhập `sv01`, vào ca thi, chọn 2–3 câu rồi nộp. Kiểm tra số đúng + sai + bỏ trống = 100.
8. App `sv02` vào cùng ca, không chọn câu nào và nộp: phải nhận 0 đúng, 0 sai, 100 bỏ trống khi điểm được công bố.
9. Web giảng viên bấm Xem thống kê: phải thấy hai bài và thống kê tương ứng.

Một sinh viên có một bài làm mỗi ca. Muốn thi lại, tạo ca mới. Bấm vào lại ca đã nộp sẽ xem kết quả, không tạo lượt mới.

## 6. Chạy Flutter

Terminal 2 tại thư mục có pubspec.yaml:

```powershell
cd "D:\BT\DIDONG\B5\Kiemtra\kiemtragk"
flutter pub get
flutter analyze
flutter test
flutter devices
```

Chọn MỘT cách:

**Chrome, tiện nhất để thử trên máy:**

```powershell
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:5000
```

Backend Development chỉ cho phép CORS từ localhost:5173 và 127.0.0.1:5173. Dùng đúng cổng này.

**Android Emulator:** mở emulator rồi thay `EMULATOR_ID` bằng ID từ flutter devices:

```powershell
flutter run -d EMULATOR_ID --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

`10.0.2.2` là địa chỉ máy chủ của Android Emulator. Không dùng localhost trong emulator. HTTP cleartext chỉ được bật trong manifest debug; bản release cần backend HTTPS hợp lệ.

**Windows desktop** nếu máy đã có bộ công cụ build Windows:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:5000
```

Không tắt kiểm tra chứng chỉ HTTPS trong code. Profile HTTP chỉ dành cho phát triển local. Chưa cấu hình cho điện thoại thật hoặc triển khai Internet.

## 7. Kiểm tra hành vi quan trọng

- Mật khẩu sai phải bị từ chối; app không tự cho đăng nhập như giao diện minh họa cũ.
- Sinh viên không được thấy ca không phân công và không gọi được API teacher (403).
- Ca tương lai/hết hạn vào thi không tạo bài mới. Bài đang làm vẫn có thể tiếp tục đến DeadlineAt.
- Chọn đáp án, tải lại bài: đáp án, đánh dấu và thứ tự đã lưu không đổi.
- Bỏ chọn, tải lại: câu trở thành bỏ trống.
- Hai tab cùng bài: server dùng revision; nếu xung đột, tải lại trước khi tiếp tục.
- Ngắt kết nối backend khi chọn: app không báo đã lưu; nối lại và “Tải lại bài” để xác nhận trạng thái server.
- Nộp nhiều lần chỉ chấm một lần; bài đã nộp không sửa được đáp án.
- Thử tự nộp bằng ca ngắn: cho bắt đầu trước hiện tại, hạn vào trong 1 phút, kết thúc trong 2 phút. Mở bài rồi đóng app. Giữ backend chạy, sau hết giờ và một lượt quét, mở lại phải thấy đã nộp.
- Chưa công bố điểm: response API không chứa số đúng/sai/bỏ trống. Sau công bố, tải lại để xem.
- Xem network API khi đang thi: không được có AnswerKey/CorrectChoiceId/Hint/Explanation.

`Database/03_SmokeTest_Rollback.sql` là bài kiểm tra stored procedure trong transaction rồi rollback, không phải dữ liệu bài thi thật. Chạy trong SSMS đúng database sau khi đã tạo schema.

## Giới hạn và phần cần làm tiếp

1. Chưa có importer Word .docx/tag đầy đủ (bảng, ảnh, BLANK, báo cáo nhiều lỗi, rollback media). JSON hiện nhận văn bản thuần; không dùng HTML tùy ý làm bài đọc. Không quảng bá JSON là đã hoàn thành yêu cầu import Word.
2. Chưa đưa nội dung/ảnh/đáp án thực của Reading v10 vào database. Không được dùng đề kỹ thuật làm đề nộp chính thức.
3. Chưa khớp đầy đủ hai thiết kế Stitch. File ZIP không chứa mã xuất từ Stitch; giữ giao diện cũ để tham khảo, trang mới là giao diện chức năng nối dữ liệu. Cần link dự án sinh viên hoặc mã xuất hai giao diện để đối chiếu tiếp.
4. Chưa có sửa bản nháp đã lưu/phiên bản mới trong cùng đề, đóng/hủy ca trên UI, quản lý lớp đầy đủ, trang xem lại đáp án/gợi ý sau giờ công bố. Chỉnh JSON trước khi nhập; không sửa DB trực tiếp để thay nội dung đề đã xuất bản.
5. Chưa có bài tập luyện tập riêng ngoài các ca thi, nhập sinh viên hàng loạt, xuất báo cáo Word, GitHub/video demo.
6. Schema nghiệp vụ single-tenant; API chỉ nhận Host để tránh lẫn dữ liệu các tenant. Nếu sau này cần nhiều trường/tenant phải thiết kế tenant isolation trước.
7. 100 điểm hiển thị là số câu đúng Reading, không phải điểm TOEIC quy đổi 495 hay tổng 990.
8. Chưa kiểm thử .NET/Flutter/SQL runtime tại môi trường soạn bản cập nhật vì thiếu các runtime đó. Đã kiểm tra cú pháp JavaScript, cấu trúc JSON/XML và số lượng câu mẫu; đã thêm test C# và Dart để chạy trên máy bạn. Không có tuyên bố đã build/chạy thành công trên máy bạn.

Ưu tiên mốc kế tiếp: chạy được luồng ở mục 5, gửi lỗi nếu có; sau đó làm importer Word + nội dung đề thật, rồi khớp Stitch và hoàn thiện báo cáo.
