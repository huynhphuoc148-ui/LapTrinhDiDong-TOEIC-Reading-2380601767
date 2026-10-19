# Quy ước nhập đề TOEIC Reading từ Word

File phải là `.docx` có text Word thật và các thẻ dưới đây. Ảnh chụp toàn trang PDF, kể cả khi đặt trong `.docx`, không thay cho nội dung câu hỏi có cấu trúc. Bộ `Reading v10.docx` đang có trong thư mục này chỉ chứa 31 ảnh trang, không có text câu hỏi, answer, hint hoặc explanation nên importer sẽ từ chối; cần bản Word đã gắn thẻ và đáp án/gợi ý/giải thích được giảng viên xác minh.

## Thẻ cấp đề và Part

Mỗi thẻ đặt ở đầu một paragraph riêng, viết đúng chữ hoa:

| Thẻ                                | Ý nghĩa                                            |
| ---------------------------------- | -------------------------------------------------- |
| `[TOEIC_EXAM]`                     | Bắt đầu một đề                                     |
| `[TITLE] Tên đề`                   | Tên đề, tối đa 250 ký tự                           |
| `[DURATION_MINUTES] 75`            | Bài Reading chính thức phải đúng 75 phút           |
| `[PART 5]`, `[PART 6]`, `[PART 7]` | Bắt đầu Part                                       |
| `[END_PART]`                       | Kết thúc Part                                      |
| `[GROUP]` / `[END_GROUP]`          | Nhóm đoạn đọc và câu liên quan của Part 6/7        |
| `[SHUFFLE_QUESTIONS] true`         | Cho phép đảo nhóm câu trong Part; mặc định `false` |

Part 5 gồm các câu độc lập, mỗi câu thành một block riêng, không dùng `[GROUP]`. Part 6 cần bốn câu trong mỗi group và mỗi số câu phải xuất hiện đúng một lần dưới dạng `{{131}}` trong passage tương ứng. Part 7 dùng group theo đoạn/bài đọc; tổng số câu Part 7 là 54.

## Thẻ câu hỏi

| Thẻ                           | Nội dung                                                              |
| ----------------------------- | --------------------------------------------------------------------- |
| `[QUESTION 101]`              | Mở câu với số gốc 101–200                                             |
| `[SHUFFLE_OPTIONS] true`      | Cho phép đảo A/B/C/D; mặc định `false`                                |
| `[STEM]`                      | Mở nội dung câu hỏi; Part 6 có thể để trống nếu câu nằm trong passage |
| `[CHOICE A]` đến `[CHOICE D]` | Mỗi thẻ mở nội dung một lựa chọn                                      |
| `[ANSWER] B`                  | Đáp án đã được người soạn xác minh; chỉ nhận A/B/C/D                  |
| `[HINT]`                      | Gợi ý đã được xác minh                                                |
| `[EXPLANATION]`               | Giải thích đã được xác minh                                           |
| `[END_QUESTION]`              | Kết thúc câu                                                          |

Nội dung của `[STEM]`, `[CHOICE ...]`, `[HINT]`, `[EXPLANATION]` và `[PASSAGE]` tiếp tục qua các paragraph/ảnh Word cho đến thẻ kế tiếp. Trong `[PASSAGE]`, paragraph và ảnh được lưu theo thứ tự xuất hiện. Ảnh hỗ trợ PNG, JPEG, GIF, WebP; tối đa 2 MB mỗi ảnh và 8 MB tổng ảnh trong một đề. Không dùng ảnh trang chụp thay cho 100 câu có cấu trúc.

## Ví dụ cấu trúc

```text
[TOEIC_EXAM]
[TITLE] Reading practice
[DURATION_MINUTES] 75
[PART 5]
[QUESTION 101]
[STEM]
Question text...
[CHOICE A]
Option A...
[CHOICE B]
Option B...
[CHOICE C]
Option C...
[CHOICE D]
Option D...
[ANSWER] B
[HINT]
Verified hint...
[EXPLANATION]
Verified explanation...
[END_QUESTION]
[END_PART]
[PART 6]
[GROUP]
[PASSAGE]
Text with the blank {{131}} in its original position.
[END_PASSAGE]
[QUESTION 131]
[CHOICE A]
...
```

Part 6/7 tiếp tục các câu trong group rồi kết thúc bằng `[END_GROUP]` và `[END_PART]`. Đề chỉ được tạo thành bản nháp sau khi toàn bộ tài liệu hợp lệ: đủ 100 câu 101–200, P5=30, P6=16, P7=54, đủ lựa chọn/answer/hint/explanation và không trùng số. Lỗi trả về kèm paragraph, Part, group hoặc số câu; không ghi một phần đề.
