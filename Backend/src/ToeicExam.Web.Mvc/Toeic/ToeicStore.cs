using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Abp.UI;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace ToeicExam.Web.Toeic;

// The domain schema is single-tenant. Controllers explicitly restrict access to host users.
// All values are parameterized. No student-supplied person/account identifier is trusted.
public sealed class ToeicStore : IAsyncDisposable
{
    private static readonly Regex EmbeddedImage = new(@"\[\[TOEIC_IMAGE:(data:image/(?:png|jpeg|gif|webp);base64,([A-Za-z0-9+/=]+))\]\]", RegexOptions.Compiled);
    private readonly SqlConnection _db;
    private SqlTransaction _tx;
    public ToeicStore(IConfiguration config) => _db = new SqlConnection(config.GetConnectionString("Default"));
    public async Task Open() => await _db.OpenAsync();
    public async ValueTask DisposeAsync()
    {
        if (_tx != null) await _tx.DisposeAsync();
        await _db.DisposeAsync();
    }
    private async Task Begin() => _tx = (SqlTransaction)await _db.BeginTransactionAsync();
    private async Task Commit() { await _tx.CommitAsync(); await _tx.DisposeAsync(); _tx = null; }
    public async Task<List<Dictionary<string, object>>> Query(string sql, params (string, object)[] values)
    {
        await using var cmd = new SqlCommand(sql, _db, _tx) { CommandTimeout = 30 };
        foreach (var (name, value) in values) cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
        var rows = new List<Dictionary<string, object>>();
        await using var reader = await cmd.ExecuteReaderAsync();
        do
        {
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object>();
                for (var i = 0; i < reader.FieldCount; i++)
                {
                    var key = reader.GetName(i);
                    var value = reader.IsDBNull(i) ? null : reader.GetValue(i);
                    if (value is DateTime date) value = DateTime.SpecifyKind(date, DateTimeKind.Utc);
                    row[char.ToLowerInvariant(key[0]) + key.Substring(1)] = value;
                }
                rows.Add(row);
            }
        } while (await reader.NextResultAsync());
        return rows;
    }
    private async Task<long> Insert(string sql, params (string, object)[] values) =>
        Convert.ToInt64((await Query(sql, values)).Single()["id"]);
    private static void Require(bool condition, string message) { if (!condition) throw new UserFriendlyException(message); }
    private static bool IsValidRichContent(string content, int maxTextLength, out int imageBytes)
    {
        imageBytes = 0;
        if (content == null) return false;
        var matches = EmbeddedImage.Matches(content);
        if (EmbeddedImage.Replace(content, string.Empty).Contains(WordExamImporter.ImageTokenPrefix, StringComparison.Ordinal)) return false;
        if (EmbeddedImage.Replace(content, string.Empty).Length > maxTextLength) return false;
        foreach (Match match in matches)
        {
            try
            {
                var bytes = Convert.FromBase64String(match.Groups[2].Value);
                if (bytes.Length == 0 || bytes.Length > 2_000_000) return false;
                imageBytes += bytes.Length;
            }
            catch (FormatException) { return false; }
        }
        return true;
    }

    public static IReadOnlyList<string> GetExamValidationErrors(ExamInput exam)
    {
        var errors = new List<string>();
        if (exam == null) return new[] { "Thiếu dữ liệu đề thi." };
        if (string.IsNullOrWhiteSpace(exam.Title) || exam.Title.Length > 250)
            errors.Add("Tên đề không hợp lệ (tối đa 250 ký tự).");
        if (exam.Blocks == null || exam.Blocks.Count == 0 || exam.Blocks.Count > 100)
            errors.Add("Cần từ 1 đến 100 nhóm câu hỏi.");
        if (exam.Blocks == null) return errors;

        var numbers = new HashSet<int>();
        var totalImageBytes = 0;
        for (var blockIndex = 0; blockIndex < exam.Blocks.Count; blockIndex++)
        {
            var block = exam.Blocks[blockIndex];
            if (block == null)
            {
                errors.Add($"Nhóm {blockIndex + 1}: dữ liệu nhóm không hợp lệ.");
                continue;
            }
            var context = $"Part {block.Part}, nhóm {blockIndex + 1}";
            if (block.Part is not 5 and not 6 and not 7)
            {
                errors.Add($"{context}: Part chỉ nhận 5, 6 hoặc 7.");
                continue;
            }
            if (block.Questions == null || block.Questions.Count == 0 || block.Questions.Count > 100)
            {
                errors.Add($"{context}: nhóm phải có từ 1 đến 100 câu.");
                continue;
            }
            if (block.Passages == null || block.Passages.Count > 10)
                errors.Add($"{context}: tối đa 10 đoạn đọc.");
            else
            {
                for (var passageIndex = 0; passageIndex < block.Passages.Count; passageIndex++)
                {
                    var passage = block.Passages[passageIndex];
                    if (string.IsNullOrWhiteSpace(passage) || !IsValidRichContent(passage, 100_000, out var passageImages))
                        errors.Add($"{context}, đoạn đọc {passageIndex + 1}: rỗng, quá dài hoặc ảnh không hợp lệ.");
                    else totalImageBytes += passageImages;
                }
            }
            if (block.Part == 5 && block.Questions.Count != 1)
                errors.Add($"{context}: Part 5 mỗi nhóm chỉ chứa một câu.");
            if (block.Part == 6 && block.Questions.Count != 4)
                errors.Add($"{context}: Part 6 mỗi nhóm phải chứa bốn câu.");
            if (block.Part != 5 && (block.Passages == null || block.Passages.Count == 0))
                errors.Add($"{context}: Part 6/7 cần ít nhất một đoạn đọc.");

            foreach (var question in block.Questions)
            {
                if (question == null)
                {
                    errors.Add($"{context}: có câu hỏi rỗng.");
                    continue;
                }
                var questionContext = $"{context}, câu {question.Number}";
                var range = block.Part == 5 ? (101, 130) : block.Part == 6 ? (131, 146) : (147, 200);
                if (question.Number < range.Item1 || question.Number > range.Item2)
                    errors.Add($"{questionContext}: số câu không thuộc dải {range.Item1}–{range.Item2} của Part.");
                else if (!numbers.Add(question.Number)) errors.Add($"{questionContext}: số câu bị trùng.");

                var stemImages = 0;
                var stemValid = string.IsNullOrWhiteSpace(question.Stem)
                    ? block.Part == 6
                    : IsValidRichContent(question.Stem, 20_000, out stemImages);
                if (!stemValid)
                    errors.Add($"{questionContext}: thiếu nội dung câu hỏi hoặc ảnh không hợp lệ.");
                else totalImageBytes += stemImages;
                if (string.IsNullOrWhiteSpace(question.Hint) ||
                    !IsValidRichContent(question.Hint, 20_000, out var hintImages))
                    errors.Add($"{questionContext}: thiếu gợi ý hoặc nội dung vượt giới hạn.");
                else totalImageBytes += hintImages;
                if (string.IsNullOrWhiteSpace(question.Explanation) ||
                    !IsValidRichContent(question.Explanation, 20_000, out var explanationImages))
                    errors.Add($"{questionContext}: thiếu giải thích hoặc nội dung vượt giới hạn.");
                else totalImageBytes += explanationImages;

                if (question.Choices == null || question.Choices.Count != 4 ||
                    !new[] { "A", "B", "C", "D" }.All(label => question.Choices.ContainsKey(label) &&
                        !string.IsNullOrWhiteSpace(question.Choices[label]) &&
                        IsValidRichContent(question.Choices[label], 20_000, out _)))
                    errors.Add($"{questionContext}: cần đủ bốn lựa chọn A/B/C/D, mỗi lựa chọn có nội dung hợp lệ.");
                else
                {
                    foreach (var choice in question.Choices.Values)
                    {
                        IsValidRichContent(choice, 20_000, out var choiceImages);
                        totalImageBytes += choiceImages;
                    }
                }
                if (question.Answer == null || question.Choices == null || !question.Choices.ContainsKey(question.Answer))
                    errors.Add($"{questionContext}: đáp án đúng phải là A, B, C hoặc D.");

                if (block.Part == 6 && block.Passages != null)
                {
                    var references = block.Passages.Sum(passage =>
                        Regex.Matches(passage ?? string.Empty, "\\{\\{" + question.Number + "\\}\\}").Count);
                    if (references != 1)
                        errors.Add($"{questionContext}: Part 6 cần đúng một chỗ trống {{{{{question.Number}}}}} trong đoạn đọc.");
                }
            }
        }
        if (numbers.Count != 100) errors.Add($"Đề Reading cần đủ 100 số câu 101–200; hiện có {numbers.Count} số duy nhất hợp lệ.");
        if (totalImageBytes > 8_000_000) errors.Add("Tổng dung lượng ảnh trong đề vượt quá 8 MB.");
        return errors;
    }

    public async Task<long> Person(long userId)
    {
        // Validate account state on every API request, including requests using a previously issued JWT.
        var users = await Query("SELECT Name,Surname FROM AbpUsers WHERE Id=@u AND TenantId IS NULL AND IsDeleted=0 AND IsActive=1", ("@u", userId));
        Require(users.Count == 1, "Tài khoản không hoạt động hoặc không thuộc hệ thống thi.");
        var name = $"{users[0]["surname"]} {users[0]["name"]}".Trim();
        var key = "host:" + userId;
        var row = await Query(@"SET XACT_ABORT ON; BEGIN TRAN;
IF NOT EXISTS(SELECT 1 FROM toeic.Person WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@key)
 INSERT toeic.Person(AccountId,FullName) VALUES(@key,@name);
SELECT Id,IsActive FROM toeic.Person WHERE AccountId=@key; COMMIT;", ("@key", key), ("@name", name));
        Require((bool)row.Single()["isActive"], "Hồ sơ đã bị khóa.");
        return Convert.ToInt64(row.Single()["id"]);
    }
    public async Task<object> Students() => await Query(@"SELECT Id,UserName,Name,Surname,EmailAddress FROM AbpUsers
WHERE TenantId IS NULL AND IsDeleted=0 AND IsActive=1 ORDER BY UserName");
    public async Task<object> Exams(long person) => await Query(@"SELECT v.Id,v.ExamId,e.Title,v.Status,v.DurationMinutes,v.ExpectedQuestions
FROM toeic.ExamVersion v JOIN toeic.Exam e ON e.Id=v.ExamId WHERE e.OwnerId=@p ORDER BY v.Id DESC", ("@p", person));

    public static void ValidateExam(ExamInput exam)
    {
        var errors = GetExamValidationErrors(exam);
        if (errors.Count > 0) throw new UserFriendlyException(string.Join(Environment.NewLine, errors));
    }
    public async Task<long> CreateExam(long person, ExamInput exam)
    {
        ValidateExam(exam);
        await Begin();
        var examId = await Insert("INSERT toeic.Exam(Title,OwnerId) OUTPUT inserted.Id VALUES(@t,@p)", ("@t", exam.Title), ("@p", person));
        var version = await InsertVersionContents(examId, 1, exam);
        await Commit();
        return version;
    }

    private async Task<long> InsertVersionContents(long examId, int versionNo, ExamInput exam)
    {
        var version = await Insert(@"INSERT toeic.ExamVersion(ExamId,VersionNo,DurationMinutes,ExpectedQuestions)
OUTPUT inserted.Id VALUES(@e,@n,75,100)", ("@e", examId), ("@n", versionNo));
        var order = 0;
        foreach (var b in exam.Blocks)
        {
            var block = await Insert("INSERT toeic.QuestionBlock(VersionId,PartNo,OriginalOrder,AllowShuffle) OUTPUT inserted.Id VALUES(@v,@p,@o,@s)", ("@v", version), ("@p", b.Part), ("@o", ++order), ("@s", b.Shuffle));
            var passageOrder = 0;
            foreach (var passage in b.Passages)
                // Plain text in this milestone: encoded on write and decoded only to plain text on read.
                await Query("INSERT toeic.Passage(BlockId,DisplayOrder,ContentHtml) VALUES(@b,@o,@text)", ("@b", block), ("@o", ++passageOrder), ("@text", System.Net.WebUtility.HtmlEncode(passage)));
            var questionOrder = 0;
            foreach (var q in b.Questions)
            {
                var question = await Insert(@"INSERT toeic.Question(VersionId,BlockId,OriginalNumber,OrderInBlock,Stem,Hint,Explanation,AllowShuffleOptions)
OUTPUT inserted.Id VALUES(@v,@b,@n,@o,@s,@h,@e,@shuffle)", ("@v", version), ("@b", block), ("@n", q.Number), ("@o", ++questionOrder), ("@s", q.Stem), ("@h", q.Hint), ("@e", q.Explanation), ("@shuffle", q.ShuffleOptions));
                foreach (var label in new[] { "A", "B", "C", "D" })
                {
                    var choice = await Insert("INSERT toeic.Choice(QuestionId,OriginalLabel,Content) OUTPUT inserted.Id VALUES(@q,@l,@c)", ("@q", question), ("@l", label), ("@c", q.Choices[label]));
                    if (label == q.Answer) await Query("INSERT toeic.AnswerKey VALUES(@q,@c)", ("@q", question), ("@c", choice));
                }
            }
        }
        return version;
    }

    public async Task<ExamInput> Draft(long person, long versionId)
    {
        var versions = await Query(@"SELECT e.Title FROM toeic.ExamVersion v
JOIN toeic.Exam e ON e.Id=v.ExamId
WHERE v.Id=@v AND v.Status='Draft' AND e.OwnerId=@p", ("@v", versionId), ("@p", person));
        Require(versions.Count == 1, "Không tìm thấy bản nháp của giảng viên này.");

        var exam = new ExamInput { Title = (string)versions[0]["title"] };
        var blocks = await Query(@"SELECT Id,PartNo,AllowShuffle FROM toeic.QuestionBlock
WHERE VersionId=@v ORDER BY PartNo,OriginalOrder", ("@v", versionId));
        foreach (var row in blocks)
        {
            var blockId = Convert.ToInt64(row["id"]);
            var block = new BlockInput
            {
                Part = Convert.ToInt32(row["partNo"]),
                Shuffle = (bool)row["allowShuffle"]
            };
            var passages = await Query("SELECT ContentHtml FROM toeic.Passage WHERE BlockId=@b ORDER BY DisplayOrder", ("@b", blockId));
            block.Passages = passages.Select(passage => System.Net.WebUtility.HtmlDecode((string)passage["contentHtml"])).ToList();

            var questions = await Query(@"SELECT Id,OriginalNumber,Stem,Hint,Explanation,AllowShuffleOptions
FROM toeic.Question WHERE BlockId=@b ORDER BY OrderInBlock", ("@b", blockId));
            foreach (var questionRow in questions)
            {
                var questionId = Convert.ToInt64(questionRow["id"]);
                var question = new QuestionInput
                {
                    Number = Convert.ToInt32(questionRow["originalNumber"]),
                    Stem = (string)questionRow["stem"],
                    Hint = (string)questionRow["hint"],
                    Explanation = (string)questionRow["explanation"],
                    ShuffleOptions = (bool)questionRow["allowShuffleOptions"]
                };
                var choices = await Query(@"SELECT c.OriginalLabel,c.Content,
CASE WHEN k.CorrectChoiceId=c.Id THEN 1 ELSE 0 END IsAnswer
FROM toeic.Choice c LEFT JOIN toeic.AnswerKey k ON k.QuestionId=c.QuestionId
WHERE c.QuestionId=@q ORDER BY c.OriginalLabel", ("@q", questionId));
                foreach (var choice in choices)
                {
                    var label = (string)choice["originalLabel"];
                    question.Choices[label] = (string)choice["content"];
                    if (Convert.ToInt32(choice["isAnswer"]) == 1) question.Answer = label;
                }
                block.Questions.Add(question);
            }
            exam.Blocks.Add(block);
        }
        return exam;
    }

    public async Task<long> UpdateDraft(long person, long versionId, ExamInput exam)
    {
        ValidateExam(exam);
        await Begin();
        var current = await Query(@"SELECT v.ExamId,v.VersionNo FROM toeic.ExamVersion v WITH(UPDLOCK,HOLDLOCK)
JOIN toeic.Exam e ON e.Id=v.ExamId
WHERE v.Id=@v AND v.Status='Draft' AND e.OwnerId=@p", ("@v", versionId), ("@p", person));
        Require(current.Count == 1, "Chỉ có thể sửa bản nháp thuộc giảng viên đang đăng nhập.");
        Require((await Query("SELECT TOP(1) Id FROM toeic.Attempt WITH(UPDLOCK,HOLDLOCK) WHERE VersionId=@v", ("@v", versionId))).Count == 0,
            "Phiên bản đã có lượt thi và không thể chỉnh sửa.");

        var examId = Convert.ToInt64(current[0]["examId"]);
        var versions = await Query("SELECT ISNULL(MAX(VersionNo),0) MaxVersionNo FROM toeic.ExamVersion WHERE ExamId=@e", ("@e", examId));
        var nextVersion = Convert.ToInt32(versions[0]["maxVersionNo"]) + 1;
        await Query("UPDATE toeic.ExamVersion SET Status='Archived' WHERE Id=@v AND Status='Draft'", ("@v", versionId));
        var newVersion = await InsertVersionContents(examId, nextVersion, exam);
        await Commit();
        return newVersion;
    }

    public async Task Publish(long person, long version)
    {
        Require((await Query("SELECT e.Id FROM toeic.Exam e JOIN toeic.ExamVersion v ON v.ExamId=e.Id WHERE v.Id=@v AND e.OwnerId=@p", ("@v", version), ("@p", person))).Count == 1, "Không có quyền với đề này.");
        await Query("EXEC toeic.PublishVersion @VersionId=@v", ("@v", version));
    }
    public async Task<long> CreateSession(long person, SessionInput input)
    {
        Require(input != null && !string.IsNullOrWhiteSpace(input.Name) && input.Name.Length <= 200, "Thiếu tên ca thi.");
        Require(new[] { "Morning", "Afternoon", "Evening", "Other" }.Contains(input.Shift), "Ca thi không hợp lệ.");
        Require(input.StartsAt < input.EntryClosesAt && input.EntryClosesAt < input.EndsAt && input.EndsAt > DateTimeOffset.UtcNow, "Cần giờ bắt đầu < hạn vào thi < giờ kết thúc, kết thúc ở tương lai.");
        Require(input.CandidateUserIds != null && input.CandidateUserIds.Count > 0 && input.CandidateUserIds.Count <= 500, "Chọn từ 1 đến 500 tài khoản dự thi.");
        Require(!input.ScoreReleaseAt.HasValue || input.ScoreReleaseAt >= input.StartsAt, "Giờ công bố điểm không trước giờ thi.");
        await Begin();
        Require((await Query(@"SELECT v.Id FROM toeic.ExamVersion v WITH(UPDLOCK,HOLDLOCK) JOIN toeic.Exam e ON e.Id=v.ExamId
WHERE v.Id=@v AND v.Status='Published' AND e.OwnerId=@p", ("@v", input.VersionId), ("@p", person))).Count == 1, "Chọn đề đã xuất bản thuộc giảng viên.");
        var people = new List<long>();
        foreach (var user in input.CandidateUserIds.Distinct())
        {
            var found = await Query("SELECT Id,Name,Surname FROM AbpUsers WHERE Id=@u AND TenantId IS NULL AND IsDeleted=0 AND IsActive=1", ("@u", user));
            Require(found.Count == 1, "Tài khoản dự thi không hợp lệ: " + user);
            var key = "host:" + user;
            var rows = await Query(@"IF NOT EXISTS(SELECT 1 FROM toeic.Person WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@a)
INSERT toeic.Person(AccountId,FullName) VALUES(@a,@n);
SELECT Id,IsActive FROM toeic.Person WHERE AccountId=@a", ("@a", key), ("@n", $"{found[0]["surname"]} {found[0]["name"]}".Trim()));
            Require((bool)rows[0]["isActive"], "Hồ sơ dự thi bị khóa.");
            people.Add(Convert.ToInt64(rows[0]["id"]));
        }
        var id = await Insert(@"INSERT toeic.ExamSession(VersionId,TeacherId,Name,Shift,StartsAt,EntryClosesAt,EndsAt,Status,ScoreReleaseAt)
OUTPUT inserted.Id VALUES(@v,@p,@n,@shift,@start,@entry,@end,'Published',@score)", ("@v", input.VersionId), ("@p", person), ("@n", input.Name), ("@shift", input.Shift), ("@start", input.StartsAt.UtcDateTime), ("@entry", input.EntryClosesAt.UtcDateTime), ("@end", input.EndsAt.UtcDateTime), ("@score", input.ScoreReleaseAt?.UtcDateTime));
        foreach (var p in people) await Query("INSERT toeic.SessionCandidate VALUES(@s,@p)", ("@s", id), ("@p", p));
        await Commit();
        return id;
    }
    public async Task<object> Sessions(long person, bool teacher) => await Query(teacher ? @"
SELECT s.*,e.Title,v.DurationMinutes,st.SubmittedAttempts,st.AverageCorrect,st.AveragePercent,
(SELECT COUNT(*) FROM toeic.SessionCandidate c WHERE c.SessionId=s.Id) CandidateCount
FROM toeic.ExamSession s JOIN toeic.ExamVersion v ON v.Id=s.VersionId JOIN toeic.Exam e ON e.Id=v.ExamId
JOIN toeic.vSessionStatistics st ON st.SessionId=s.Id WHERE s.TeacherId=@p ORDER BY s.StartsAt DESC" : @"
SELECT s.Id,s.Name,s.Shift,s.StartsAt,s.EntryClosesAt,s.EndsAt,s.Status,s.ScoreReleaseAt,e.Title,v.DurationMinutes,
a.Id AttemptId,a.Status AttemptStatus,a.DeadlineAt,SYSUTCDATETIME() ServerNow
FROM toeic.ExamSession s JOIN toeic.ExamVersion v ON v.Id=s.VersionId JOIN toeic.Exam e ON e.Id=v.ExamId
JOIN toeic.SessionCandidate c ON c.SessionId=s.Id AND c.PersonId=@p
LEFT JOIN toeic.Attempt a ON a.SessionId=s.Id AND a.PersonId=@p
WHERE s.Status<>'Draft' ORDER BY s.StartsAt DESC", ("@p", person));

    public async Task<Guid> Start(long person, long session)
    {
        await Begin();
        var sessions = await Query(@"SELECT s.*,v.DurationMinutes,v.ExpectedQuestions,SYSUTCDATETIME() ServerNow FROM toeic.ExamSession s WITH(UPDLOCK,HOLDLOCK)
JOIN toeic.ExamVersion v ON v.Id=s.VersionId JOIN toeic.SessionCandidate c ON c.SessionId=s.Id AND c.PersonId=@p WHERE s.Id=@s", ("@p", person), ("@s", session));
        Require(sessions.Count == 1, "Bạn không nằm trong danh sách dự thi.");
        var s = sessions[0];
        var existing = await Query("SELECT Id FROM toeic.Attempt WHERE SessionId=@s AND PersonId=@p", ("@s", session), ("@p", person));
        if (existing.Count > 0) { await Commit(); return (Guid)existing[0]["id"]; }
        var now = (DateTime)s["serverNow"];
        Require((string)s["status"] == "Published" && now >= (DateTime)s["startsAt"] && now < (DateTime)s["entryClosesAt"], "Ca chưa mở, đã hết hạn vào thi hoặc đã khóa.");
        var version = Convert.ToInt64(s["versionId"]);
        var deadline = now.AddMinutes(Convert.ToInt32(s["durationMinutes"]));
        if (deadline > (DateTime)s["endsAt"]) deadline = (DateTime)s["endsAt"];
        var attempt = Guid.NewGuid();
        await Query(@"INSERT toeic.Attempt(Id,SessionId,VersionId,PersonId,StartedAt,DeadlineAt)
VALUES(@a,@s,@v,@p,@n,@d)", ("@a", attempt), ("@s", session), ("@v", version), ("@p", person), ("@n", now), ("@d", deadline));
        var blocks = await Query("SELECT Id,PartNo,AllowShuffle FROM toeic.QuestionBlock WHERE VersionId=@v ORDER BY PartNo,OriginalOrder", ("@v", version));
        var display = 0;
        foreach (var part in blocks.GroupBy(b => Convert.ToInt32(b["partNo"])))
        {
            var ordered = part.ToList();
            var slots = Enumerable.Range(0, ordered.Count).Where(i => (bool)ordered[i]["allowShuffle"]).ToArray();
            var movable = slots.Select(i => ordered[i]).ToArray();
            Random.Shared.Shuffle(movable);
            for (var i = 0; i < slots.Length; i++) ordered[slots[i]] = movable[i];
            foreach (var block in ordered)
            {
                var questions = await Query("SELECT Id,AllowShuffleOptions FROM toeic.Question WHERE BlockId=@b ORDER BY OrderInBlock", ("@b", block["id"]));
                foreach (var q in questions)
                {
                    await Query("INSERT toeic.AttemptQuestion VALUES(@a,@v,@q,@o)", ("@a", attempt), ("@v", version), ("@q", q["id"]), ("@o", ++display));
                    var choices = (await Query("SELECT Id FROM toeic.Choice WHERE QuestionId=@q ORDER BY OriginalLabel", ("@q", q["id"]))).ToArray();
                    if ((bool)q["allowShuffleOptions"]) Random.Shared.Shuffle(choices);
                    for (var i = 0; i < choices.Length; i++) await Query("INSERT toeic.AttemptChoice VALUES(@a,@q,@c,@l)", ("@a", attempt), ("@q", q["id"]), ("@c", choices[i]["id"]), ("@l", ((char)('A' + i)).ToString()));
                }
            }
        }
        Require(display == Convert.ToInt32(s["expectedQuestions"]), "Đề không đủ câu, chưa tạo bài làm.");
        await Commit();
        return attempt;
    }
    public async Task<object> Attempt(long person, Guid id)
    {
        var rows = await Query(@"SELECT a.Id,a.SessionId,a.Status,a.ActiveLeaseId,a.DeadlineAt,a.SubmittedAt,
s.Name,s.Status SessionStatus,s.ScoreReleaseAt,e.Title,SYSUTCDATETIME() ServerNow,
CASE WHEN s.ScoreReleaseAt<=SYSUTCDATETIME() AND a.Status='Submitted' THEN a.CorrectCount END CorrectCount,
CASE WHEN s.ScoreReleaseAt<=SYSUTCDATETIME() AND a.Status='Submitted' THEN a.WrongCount END WrongCount,
CASE WHEN s.ScoreReleaseAt<=SYSUTCDATETIME() AND a.Status='Submitted' THEN a.SkippedCount END SkippedCount
FROM toeic.Attempt a JOIN toeic.ExamSession s ON s.Id=a.SessionId JOIN toeic.ExamVersion v ON v.Id=a.VersionId
JOIN toeic.Exam e ON e.Id=v.ExamId WHERE a.Id=@a AND a.PersonId=@p", ("@a", id), ("@p", person));
        Require(rows.Count == 1, "Không tìm thấy bài làm của bạn.");
        var row = rows[0];
        if ((string)row["status"] == "InProgress" && (DateTime)row["serverNow"] >= (DateTime)row["deadlineAt"] && new[] { "Published", "Closed" }.Contains((string)row["sessionStatus"]))
        {
            await Submit(person, id);
            return await Attempt(person, id);
        }
        // No keys/hints/explanations, including after submission until a separate review policy is implemented.
        if ((string)row["status"] != "InProgress" || (string)row["sessionStatus"] != "Published") return new { attempt = row, questions = Array.Empty<object>() };
        var questions = await Query(@"SELECT q.Id,q.BlockId,b.PartNo,q.OriginalNumber,q.Stem,aq.DisplayOrder,
r.ChoiceId,ISNULL(r.MarkedForReview,0) MarkedForReview,ISNULL(r.Revision,0) Revision
FROM toeic.AttemptQuestion aq JOIN toeic.Question q ON q.Id=aq.QuestionId JOIN toeic.QuestionBlock b ON b.Id=q.BlockId
LEFT JOIN toeic.Response r ON r.AttemptId=aq.AttemptId AND r.QuestionId=q.Id WHERE aq.AttemptId=@a ORDER BY aq.DisplayOrder", ("@a", id));
        var choices = await Query(@"SELECT ac.QuestionId,ac.ChoiceId,ac.DisplayLabel,c.Content FROM toeic.AttemptChoice ac
JOIN toeic.Choice c ON c.Id=ac.ChoiceId WHERE ac.AttemptId=@a ORDER BY ac.DisplayLabel", ("@a", id));
        var passages = await Query(@"SELECT p.BlockId,p.ContentHtml,p.DisplayOrder FROM toeic.Passage p WHERE EXISTS(
SELECT 1 FROM toeic.AttemptQuestion aq JOIN toeic.Question q ON q.Id=aq.QuestionId WHERE aq.AttemptId=@a AND q.BlockId=p.BlockId) ORDER BY p.DisplayOrder", ("@a", id));
        foreach (var q in questions)
        {
            q["choices"] = choices.Where(c => Equals(c["questionId"], q["id"])).ToArray();
            q["passages"] = passages.Where(p => Equals(p["blockId"], q["blockId"])).Select(p => System.Net.WebUtility.HtmlDecode((string)p["contentHtml"])).ToArray();
        }
        return new { attempt = row, questions };
    }
    public async Task<object> Save(long person, Guid attempt, SaveInput input)
    {
        Require(input != null, "Thiếu câu trả lời.");
        return (await Query(@"EXEC toeic.SaveResponse @AttemptId=@a,@PersonId=@p,@LeaseId=@l,@QuestionId=@q,
@ChoiceId=@c,@MarkedForReview=@m,@Revision=@r", ("@a", attempt), ("@p", person), ("@l", input.LeaseId), ("@q", input.QuestionId), ("@c", input.ChoiceId), ("@m", input.MarkedForReview), ("@r", input.Revision))).Single();
    }
    public async Task Submit(long person, Guid id) => await Query("EXEC toeic.SubmitAttempt @AttemptId=@a,@PersonId=@p", ("@a", id), ("@p", person));
    public async Task<object> ExamStatistics(long person, long exam)
    {
        Require((await Query("SELECT Id FROM toeic.Exam WHERE Id=@e AND OwnerId=@p", ("@e", exam), ("@p", person))).Count == 1, "Không có quyền xem đề thi.");
        return new {
            summary = (await Query(@"SELECT COUNT(a.Id) SubmittedAttempts,
AVG(CAST(a.CorrectCount AS decimal(10,2))) AverageCorrect,
AVG(100.0*a.CorrectCount/NULLIF(v.ExpectedQuestions,0)) AveragePercent
FROM toeic.ExamVersion v JOIN toeic.ExamSession s ON s.VersionId=v.Id
JOIN toeic.Attempt a ON a.SessionId=s.Id AND a.Status='Submitted'
WHERE v.ExamId=@e AND s.TeacherId=@p", ("@e", exam), ("@p", person))).Single(),
            attempts = await Query(@"SELECT p.FullName,s.Name SessionName,v.VersionNo,
a.SubmittedAt,a.CorrectCount,a.WrongCount,a.SkippedCount
FROM toeic.Attempt a JOIN toeic.Person p ON p.Id=a.PersonId
JOIN toeic.ExamSession s ON s.Id=a.SessionId JOIN toeic.ExamVersion v ON v.Id=s.VersionId
WHERE v.ExamId=@e AND s.TeacherId=@p AND a.Status='Submitted'
ORDER BY a.SubmittedAt DESC,a.Id", ("@e", exam), ("@p", person)),
            topWrong = await Query(@"SELECT TOP(10) q.QuestionId,q.OriginalNumber,v.VersionNo,
SUM(q.SeenCount) SeenCount,SUM(q.WrongCount) WrongCount,SUM(q.SkippedCount) SkippedCount
FROM toeic.vQuestionStatistics q JOIN toeic.ExamSession s ON s.Id=q.SessionId
JOIN toeic.ExamVersion v ON v.Id=q.VersionId
WHERE v.ExamId=@e AND s.TeacherId=@p
GROUP BY q.QuestionId,q.OriginalNumber,v.VersionNo
HAVING SUM(q.WrongCount)>0 ORDER BY SUM(q.WrongCount) DESC,v.VersionNo,q.OriginalNumber,q.QuestionId",
("@e", exam), ("@p", person))
        };
    }
    public async Task<object> Statistics(long person, long session)
    {
        Require((await Query("SELECT Id FROM toeic.ExamSession WHERE Id=@s AND TeacherId=@p", ("@s", session), ("@p", person))).Count == 1, "Không có quyền xem ca thi.");
        return new {
            summary = (await Query("SELECT * FROM toeic.vSessionStatistics WHERE SessionId=@s", ("@s", session))).Single(),
            attempts = await Query(@"SELECT p.FullName,a.Status,a.SubmittedAt,a.CorrectCount,a.WrongCount,a.SkippedCount
FROM toeic.Attempt a JOIN toeic.Person p ON p.Id=a.PersonId WHERE a.SessionId=@s ORDER BY p.FullName", ("@s", session)),
            topWrong = await Query("SELECT TOP(10) * FROM toeic.vQuestionStatistics WHERE SessionId=@s AND WrongCount>0 ORDER BY WrongCount DESC,OriginalNumber", ("@s", session))
        };
    }
}
