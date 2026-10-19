/*
TOEIC_ALL_IN_ONE.sql — SQL Server 2022 / SSMS
Gộp schema, procedures, statistics và kiểm thử rollback vào một file.
CÁCH CHẠY: mở file, Ctrl+Home, click vào editor để bỏ vùng chọn, F5 chạy TOÀN BỘ.
Không bôi đen một đoạn BEGIN TRY/CREATE TABLE để chạy riêng.
Nếu tab cũ có transaction dang dở: dùng tab New Query mới cho file này.
Database: ToeicExamDesignDb. Không xóa database/bảng/dữ liệu cũ.
Tạo đối tượng còn thiếu; cập nhật 3 procedures + 2 views của bộ TOEIC trước.
Không phải script migration cho bảng đã được bạn tự sửa cấu trúc.
Không bao gồm đăng nhập, import DOCX, StartAttempt/hoán vị, worker, giao diện.
Không có Word đủ 100 câu; dữ liệu test nhỏ được rollback.
Tài khoản do ASP.NET Boilerplate quản lý; schema toeic không thay AbpUsers.
Thời điểm UTC; UI đổi sang giờ Việt Nam. Phạm vi single-tenant.
Chưa chạy trên SQL Server thực tế tại môi trường soạn file.
*/
USE master;
GO
IF @@TRANCOUNT <> 0
BEGIN
    THROW 51100, N'Hãy mở tab New Query mới: kết nối hiện tại có transaction đang mở.', 1;
END;
IF DB_ID(N'ToeicExamDesignDb') IS NULL
    EXEC(N'CREATE DATABASE ToeicExamDesignDb');
GO
USE ToeicExamDesignDb;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'ToeicExamDesignDb'
BEGIN
    THROW 51101, N'Sai database; dừng thực thi.', 1;
END;
IF @@TRANCOUNT <> 0
BEGIN
    THROW 51102, N'Hãy mở New Query mới rồi chạy toàn bộ file.', 1;
END;
IF OBJECT_ID('tempdb..#ToeicSetupSuccess') IS NOT NULL DROP TABLE #ToeicSetupSuccess;
CREATE TABLE #ToeicSetupSuccess (Succeeded bit NOT NULL);
BEGIN TRY
BEGIN TRANSACTION;
IF SCHEMA_ID(N'toeic') IS NULL
    EXEC(N'CREATE SCHEMA toeic AUTHORIZATION dbo');

IF OBJECT_ID(N'toeic.Person', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Person (
 Id bigint IDENTITY PRIMARY KEY,
 AccountId nvarchar(128) NOT NULL UNIQUE,
 StudentCode nvarchar(40) NULL,
 FullName nvarchar(160) NOT NULL,
 IsActive bit NOT NULL DEFAULT 1
);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'toeic.Person') AND name=N'UX_Person_StudentCode')
    EXEC(N'CREATE UNIQUE INDEX UX_Person_StudentCode ON toeic.Person(StudentCode) WHERE StudentCode IS NOT NULL;');

IF OBJECT_ID(N'toeic.Classroom', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Classroom (
 Id bigint IDENTITY PRIMARY KEY,
 Code nvarchar(40) NOT NULL UNIQUE,
 Name nvarchar(160) NOT NULL,
 TeacherId bigint NOT NULL REFERENCES toeic.Person(Id)
);');

IF OBJECT_ID(N'toeic.ClassMember', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.ClassMember (
 ClassId bigint NOT NULL REFERENCES toeic.Classroom(Id),
 PersonId bigint NOT NULL REFERENCES toeic.Person(Id),
 PRIMARY KEY(ClassId,PersonId)
);');

IF OBJECT_ID(N'toeic.Exam', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Exam (
 Id bigint IDENTITY PRIMARY KEY,
 Title nvarchar(250) NOT NULL,
 OwnerId bigint NOT NULL REFERENCES toeic.Person(Id),
 CreatedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);');

IF OBJECT_ID(N'toeic.ExamVersion', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.ExamVersion (
 Id bigint IDENTITY PRIMARY KEY,
 ExamId bigint NOT NULL REFERENCES toeic.Exam(Id),
 VersionNo int NOT NULL CHECK(VersionNo>0),
 DurationMinutes int NOT NULL DEFAULT 75 CHECK(DurationMinutes BETWEEN 1 AND 300),
 ExpectedQuestions int NOT NULL DEFAULT 100 CHECK(ExpectedQuestions>0),
 Status varchar(12) NOT NULL DEFAULT ''Draft'' CHECK(Status IN (''Draft'',''Published'',''Archived'')),
 CreatedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 RowVer rowversion,
 UNIQUE(ExamId,VersionNo)
);');

IF OBJECT_ID(N'toeic.QuestionBlock', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.QuestionBlock (
 Id bigint IDENTITY PRIMARY KEY,
 VersionId bigint NOT NULL REFERENCES toeic.ExamVersion(Id),
 PartNo tinyint NOT NULL CHECK(PartNo IN (5,6,7)),
 OriginalOrder int NOT NULL CHECK(OriginalOrder>0),
 Instruction nvarchar(1000) NULL,
 AllowShuffle bit NOT NULL DEFAULT 0,
 UNIQUE(VersionId,PartNo,OriginalOrder),
 UNIQUE(Id,VersionId)
);');

IF OBJECT_ID(N'toeic.Passage', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Passage (
 Id bigint IDENTITY PRIMARY KEY,
 BlockId bigint NOT NULL REFERENCES toeic.QuestionBlock(Id),
 DisplayOrder int NOT NULL CHECK(DisplayOrder>0),
 Title nvarchar(250) NULL,
 ContentHtml nvarchar(max) NOT NULL,
 
 UNIQUE(BlockId,DisplayOrder)
);');

IF OBJECT_ID(N'toeic.MediaAsset', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.MediaAsset (
 Id uniqueidentifier NOT NULL DEFAULT NEWID() PRIMARY KEY,
 VersionId bigint NOT NULL REFERENCES toeic.ExamVersion(Id),
 StorageKey nvarchar(450) NOT NULL UNIQUE,
 MimeType varchar(80) NOT NULL,
 ByteCount bigint NOT NULL CHECK(ByteCount>0),
 AltText nvarchar(500) NULL
);');

IF OBJECT_ID(N'toeic.Question', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Question (
 Id bigint IDENTITY PRIMARY KEY,
 VersionId bigint NOT NULL,
 BlockId bigint NOT NULL,
 OriginalNumber int NOT NULL CHECK(OriginalNumber BETWEEN 101 AND 200),
 OrderInBlock int NOT NULL CHECK(OrderInBlock>0),
 Stem nvarchar(max) NOT NULL,
 Hint nvarchar(max) NOT NULL,
 Explanation nvarchar(max) NOT NULL,
 AllowShuffleOptions bit NOT NULL DEFAULT 0,
 FOREIGN KEY(BlockId,VersionId) REFERENCES toeic.QuestionBlock(Id,VersionId),
 UNIQUE(VersionId,OriginalNumber),
 UNIQUE(BlockId,OrderInBlock),
 UNIQUE(Id,VersionId)
);');

IF OBJECT_ID(N'toeic.Choice', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Choice (
 Id bigint IDENTITY PRIMARY KEY,
 QuestionId bigint NOT NULL REFERENCES toeic.Question(Id),
 OriginalLabel char(1) NOT NULL CHECK(OriginalLabel IN (''A'',''B'',''C'',''D'')),
 Content nvarchar(max) NOT NULL,
 UNIQUE(QuestionId,OriginalLabel),
 UNIQUE(QuestionId,Id)
);');

IF OBJECT_ID(N'toeic.AnswerKey', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.AnswerKey (
 QuestionId bigint NOT NULL PRIMARY KEY,
 CorrectChoiceId bigint NOT NULL,
 FOREIGN KEY(QuestionId,CorrectChoiceId) REFERENCES toeic.Choice(QuestionId,Id)
);');

IF OBJECT_ID(N'toeic.ExamSession', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.ExamSession (
 Id bigint IDENTITY PRIMARY KEY,
 VersionId bigint NOT NULL REFERENCES toeic.ExamVersion(Id),
 TeacherId bigint NOT NULL REFERENCES toeic.Person(Id),
 Name nvarchar(200) NOT NULL,
 Shift varchar(12) NOT NULL CHECK(Shift IN (''Morning'',''Afternoon'',''Evening'',''Other'')),
 StartsAt datetime2(3) NOT NULL,
 EntryClosesAt datetime2(3) NOT NULL,
 EndsAt datetime2(3) NOT NULL,
 Status varchar(12) NOT NULL DEFAULT ''Draft'' CHECK(Status IN (''Draft'',''Published'',''Cancelled'',''Closed'')),
 ScoreReleaseAt datetime2(3) NULL,
 ReviewReleaseAt datetime2(3) NULL,
 CancelReason nvarchar(1000) NULL,
 RowVer rowversion,
 CHECK(StartsAt<=EntryClosesAt AND EntryClosesAt<EndsAt),
 CHECK(ReviewReleaseAt IS NULL OR (ScoreReleaseAt IS NOT NULL AND ReviewReleaseAt>=ScoreReleaseAt)),
 UNIQUE(Id,VersionId)
);');

IF OBJECT_ID(N'toeic.SessionCandidate', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.SessionCandidate (
 SessionId bigint NOT NULL REFERENCES toeic.ExamSession(Id),
 PersonId bigint NOT NULL REFERENCES toeic.Person(Id),
 PRIMARY KEY(SessionId,PersonId)
);');

IF OBJECT_ID(N'toeic.Attempt', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Attempt (
 Id uniqueidentifier NOT NULL DEFAULT NEWID() PRIMARY KEY,
 SessionId bigint NOT NULL,
 VersionId bigint NOT NULL,
 PersonId bigint NOT NULL,
 StartedAt datetime2(3) NOT NULL,
 DeadlineAt datetime2(3) NOT NULL,
 Status varchar(12) NOT NULL DEFAULT ''InProgress'' CHECK(Status IN (''InProgress'',''Submitted'',''Cancelled'')),
 SubmittedAt datetime2(3) NULL,
 SubmitReason varchar(12) NULL CHECK(SubmitReason IN (''Manual'',''Timeout'')),
 CorrectCount int NULL,
 WrongCount int NULL,
 SkippedCount int NULL,
 
 ActiveLeaseId uniqueidentifier NOT NULL DEFAULT NEWID(),
 RowVer rowversion,
 CHECK(DeadlineAt>StartedAt),
 CHECK(CorrectCount IS NULL OR CorrectCount>=0),
 CHECK(WrongCount IS NULL OR WrongCount>=0),
 CHECK(SkippedCount IS NULL OR SkippedCount>=0),
 FOREIGN KEY(SessionId,VersionId) REFERENCES toeic.ExamSession(Id,VersionId),
 FOREIGN KEY(SessionId,PersonId) REFERENCES toeic.SessionCandidate(SessionId,PersonId),
 UNIQUE(SessionId,PersonId),
 UNIQUE(Id,VersionId)
);');

IF OBJECT_ID(N'toeic.AttemptQuestion', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.AttemptQuestion (
 AttemptId uniqueidentifier NOT NULL,
 VersionId bigint NOT NULL,
 QuestionId bigint NOT NULL,
 DisplayOrder int NOT NULL CHECK(DisplayOrder>0),
 PRIMARY KEY(AttemptId,QuestionId),
 FOREIGN KEY(AttemptId,VersionId) REFERENCES toeic.Attempt(Id,VersionId),
 FOREIGN KEY(QuestionId,VersionId) REFERENCES toeic.Question(Id,VersionId),
 UNIQUE(AttemptId,DisplayOrder)
);');

IF OBJECT_ID(N'toeic.AttemptChoice', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.AttemptChoice (
 AttemptId uniqueidentifier NOT NULL,
 QuestionId bigint NOT NULL,
 ChoiceId bigint NOT NULL,
 DisplayLabel char(1) NOT NULL CHECK(DisplayLabel IN (''A'',''B'',''C'',''D'')),
 PRIMARY KEY(AttemptId,QuestionId,ChoiceId),
 FOREIGN KEY(AttemptId,QuestionId) REFERENCES toeic.AttemptQuestion(AttemptId,QuestionId),
 FOREIGN KEY(QuestionId,ChoiceId) REFERENCES toeic.Choice(QuestionId,Id),
 UNIQUE(AttemptId,QuestionId,DisplayLabel)
);');

IF OBJECT_ID(N'toeic.Response', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.Response (
 AttemptId uniqueidentifier NOT NULL,
 QuestionId bigint NOT NULL,
 ChoiceId bigint NULL,
 MarkedForReview bit NOT NULL DEFAULT 0,
 Revision int NOT NULL CHECK(Revision>0),
 SavedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 PRIMARY KEY(AttemptId,QuestionId),
 FOREIGN KEY(AttemptId,QuestionId) REFERENCES toeic.AttemptQuestion(AttemptId,QuestionId),
 FOREIGN KEY(AttemptId,QuestionId,ChoiceId) REFERENCES toeic.AttemptChoice(AttemptId,QuestionId,ChoiceId)
);');

IF OBJECT_ID(N'toeic.AuditEvent', N'U') IS NULL
    EXEC(N'CREATE TABLE toeic.AuditEvent (
 Id bigint IDENTITY PRIMARY KEY,
 ActorId bigint NULL REFERENCES toeic.Person(Id),
 Action nvarchar(100) NOT NULL,
 TargetType nvarchar(80) NOT NULL,
 TargetId nvarchar(128) NOT NULL,
 Details nvarchar(max) NULL,
 CreatedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'toeic.Attempt') AND name=N'IX_Attempt_Deadline')
    EXEC(N'CREATE INDEX IX_Attempt_Deadline ON toeic.Attempt(Status,DeadlineAt);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'toeic.ExamSession') AND name=N'IX_Session_Time')
    EXEC(N'CREATE INDEX IX_Session_Time ON toeic.ExamSession(Status,StartsAt,EndsAt);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'toeic.Question') AND name=N'IX_Question_Version')
    EXEC(N'CREATE INDEX IX_Question_Version ON toeic.Question(VersionId);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'toeic.Passage') AND name=N'IX_Passage_Block')
    EXEC(N'CREATE INDEX IX_Passage_Block ON toeic.Passage(BlockId);');

-- Stored procedures và views
EXEC(N'-- Backend phải xác thực và phân quyền trước khi gọi.
-- PersonId lấy từ phiên đăng nhập, KHÔNG lấy tùy ý từ request của sinh viên.
-- Các procedure này không cấp quyền login và không thay thế API.
CREATE OR ALTER PROCEDURE toeic.PublishVersion
 @VersionId bigint
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @Status varchar(12);
 SELECT @Status=Status FROM toeic.ExamVersion WITH(UPDLOCK,HOLDLOCK) WHERE Id=@VersionId;
 IF @Status IS NULL OR @Status<>''Draft'' THROW 51001,N''Chỉ xuất bản phiên bản nháp.'',1;
 IF NOT EXISTS(SELECT 1 FROM toeic.ExamVersion WHERE Id=@VersionId AND ExpectedQuestions=100 AND DurationMinutes=75)
  THROW 51002,N''Đề Reading chính thức phải 100 câu và 75 phút.'',1;
 IF (SELECT COUNT(*) FROM toeic.Question WHERE VersionId=@VersionId)<>100
  THROW 51003,N''Đề chưa đủ 100 câu.'',1;
 IF EXISTS(
  SELECT 1 FROM toeic.Question q JOIN toeic.QuestionBlock b ON b.Id=q.BlockId
  WHERE q.VersionId=@VersionId AND
   ((b.PartNo=5 AND q.OriginalNumber NOT BETWEEN 101 AND 130)
    OR (b.PartNo=6 AND q.OriginalNumber NOT BETWEEN 131 AND 146)
    OR (b.PartNo=7 AND q.OriginalNumber NOT BETWEEN 147 AND 200)))
  THROW 51004,N''Số câu không khớp Part.'',1;
 IF EXISTS(
  SELECT 1 FROM toeic.Question q WHERE q.VersionId=@VersionId AND
   ((SELECT COUNT(*) FROM toeic.Choice c WHERE c.QuestionId=q.Id)<>4
    OR NOT EXISTS(SELECT 1 FROM toeic.AnswerKey k WHERE k.QuestionId=q.Id)
    OR LEN(LTRIM(RTRIM(q.Hint)))=0
    OR LEN(LTRIM(RTRIM(q.Explanation)))=0))
  THROW 51005,N''Câu hỏi thiếu 4 lựa chọn, đáp án, gợi ý hoặc giải thích.'',1;
 IF EXISTS(
  SELECT 1 FROM toeic.QuestionBlock b WHERE b.VersionId=@VersionId AND
   ((b.PartNo=5 AND (SELECT COUNT(*) FROM toeic.Question q WHERE q.BlockId=b.Id)<>1)
    OR (b.PartNo=6 AND (SELECT COUNT(*) FROM toeic.Question q WHERE q.BlockId=b.Id)<>4)
    OR (b.PartNo IN(6,7) AND NOT EXISTS(SELECT 1 FROM toeic.Passage p WHERE p.BlockId=b.Id))
    OR NOT EXISTS(SELECT 1 FROM toeic.Question q WHERE q.BlockId=b.Id)))
  THROW 51006,N''Nhóm câu không hợp lệ hoặc thiếu bài đọc.'',1;
 -- Parser/app phải kiểm tra thêm HTML, ảnh, nội dung lựa chọn và blank references.
 UPDATE toeic.ExamVersion SET Status=''Published'' WHERE Id=@VersionId;
 COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;');

EXEC(N'CREATE OR ALTER PROCEDURE toeic.SaveResponse
 @AttemptId uniqueidentifier, @PersonId bigint, @LeaseId uniqueidentifier,
 @QuestionId bigint, @ChoiceId bigint=NULL, @MarkedForReview bit=0, @Revision int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @State varchar(12), @Deadline datetime2(3), @SessionId bigint;
 SELECT @State=Status,@Deadline=DeadlineAt,@SessionId=SessionId
 FROM toeic.Attempt WITH(UPDLOCK,HOLDLOCK)
 WHERE Id=@AttemptId AND PersonId=@PersonId AND ActiveLeaseId=@LeaseId;
 IF @State IS NULL THROW 51010,N''Không có quyền hoặc phiên làm bài không hợp lệ.'',1;
 IF @State<>''InProgress'' OR SYSUTCDATETIME()>=@Deadline
  THROW 51011,N''Bài đã khóa hoặc hết giờ.'',1;
 IF NOT EXISTS(SELECT 1 FROM toeic.ExamSession WHERE Id=@SessionId AND Status=''Published'')
  THROW 51012,N''Ca không còn cho phép làm bài.'',1;
 IF @Revision<=0 THROW 51013,N''Revision phải lớn hơn 0.'',1;
 IF NOT EXISTS(SELECT 1 FROM toeic.AttemptQuestion WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId)
  THROW 51014,N''Câu không thuộc bài làm.'',1;
 IF @ChoiceId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM toeic.AttemptChoice WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId AND ChoiceId=@ChoiceId)
  THROW 51015,N''Lựa chọn không thuộc câu trong bài làm.'',1;
 DECLARE @OldRevision int;
 SELECT @OldRevision=Revision FROM toeic.Response WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId;
 IF @OldRevision=@Revision AND EXISTS(
 SELECT 1 FROM toeic.Response WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId
 AND (ISNULL(ChoiceId,-1)<>ISNULL(@ChoiceId,-1) OR MarkedForReview<>@MarkedForReview))
  THROW 51016,N''Cùng revision nhưng nội dung khác nhau.'',1;
 IF @OldRevision IS NULL
 INSERT toeic.Response(AttemptId,QuestionId,ChoiceId,MarkedForReview,Revision)
 VALUES(@AttemptId,@QuestionId,@ChoiceId,@MarkedForReview,@Revision);
 ELSE IF @Revision>@OldRevision
 UPDATE toeic.Response SET ChoiceId=@ChoiceId,MarkedForReview=@MarkedForReview,
 Revision=@Revision,SavedAt=SYSUTCDATETIME()
 WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId;
 -- Revision cũ không ghi đè; trả trạng thái đã lưu cho client đối chiếu.
 COMMIT;
 SELECT QuestionId,ChoiceId,MarkedForReview,Revision,SavedAt FROM toeic.Response
 WHERE AttemptId=@AttemptId AND QuestionId=@QuestionId;
 END TRY
 BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
 END CATCH
END;');

EXEC(N'CREATE OR ALTER PROCEDURE toeic.SubmitAttempt
 @AttemptId uniqueidentifier, @PersonId bigint
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @State varchar(12),@Deadline datetime2(3),@SessionId bigint,@VersionId bigint;
 SELECT @State=Status,@Deadline=DeadlineAt,@SessionId=SessionId,@VersionId=VersionId
 FROM toeic.Attempt WITH(UPDLOCK,HOLDLOCK) WHERE Id=@AttemptId AND PersonId=@PersonId;
 IF @State IS NULL THROW 51020,N''Không tìm thấy bài làm thuộc người dùng.'',1;
 IF @State=''Cancelled'' THROW 51021,N''Bài đã hủy.'',1;
 IF @State=''InProgress''
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM toeic.ExamSession WHERE Id=@SessionId AND Status IN(''Published'',''Closed''))
  THROW 51022,N''Ca bị hủy hoặc không hợp lệ.'',1;
 DECLARE @Total int,@Expected int,@Correct int,@Wrong int,@Skipped int,@Now datetime2(3)=SYSUTCDATETIME();
 SELECT @Expected=ExpectedQuestions FROM toeic.ExamVersion WHERE Id=@VersionId;
 SELECT @Total=COUNT(*) FROM toeic.AttemptQuestion WHERE AttemptId=@AttemptId;
 IF @Total<>@Expected THROW 51023,N''Bài làm chưa được khởi tạo đủ câu.'',1;
 IF EXISTS(SELECT 1 FROM toeic.AttemptQuestion aq LEFT JOIN toeic.AnswerKey k ON k.QuestionId=aq.QuestionId
 WHERE aq.AttemptId=@AttemptId AND k.QuestionId IS NULL)
  THROW 51024,N''Đề thiếu khóa đáp án.'',1;
 SELECT
 @Correct=SUM(CASE WHEN r.ChoiceId=k.CorrectChoiceId THEN 1 ELSE 0 END),
 @Wrong=SUM(CASE WHEN r.ChoiceId IS NOT NULL AND r.ChoiceId<>k.CorrectChoiceId THEN 1 ELSE 0 END),
 @Skipped=SUM(CASE WHEN r.ChoiceId IS NULL THEN 1 ELSE 0 END)
 FROM toeic.AttemptQuestion aq
 JOIN toeic.AnswerKey k ON k.QuestionId=aq.QuestionId
 LEFT JOIN toeic.Response r ON r.AttemptId=aq.AttemptId AND r.QuestionId=aq.QuestionId
 WHERE aq.AttemptId=@AttemptId;
 UPDATE toeic.Attempt SET Status=''Submitted'',SubmittedAt=@Now,
 SubmitReason=CASE WHEN @Now>=@Deadline THEN ''Timeout'' ELSE ''Manual'' END,
 CorrectCount=@Correct,WrongCount=@Wrong,SkippedCount=@Skipped
 WHERE Id=@AttemptId;
 END
 COMMIT;
 -- API phải lọc điểm nếu chưa tới ScoreReleaseAt, không trả thẳng toàn bộ record cho mobile.
 SELECT Id,Status,SubmittedAt,SubmitReason,CorrectCount,WrongCount,SkippedCount
 FROM toeic.Attempt WHERE Id=@AttemptId;
 END TRY
 BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
 END CATCH
END;');

EXEC(N'CREATE OR ALTER VIEW toeic.vSessionStatistics AS
 SELECT s.Id SessionId,s.VersionId,COUNT(a.Id) SubmittedAttempts,
 AVG(CAST(a.CorrectCount AS decimal(10,2))) AverageCorrect,
 AVG(100.0*a.CorrectCount/NULLIF(v.ExpectedQuestions,0)) AveragePercent
 FROM toeic.ExamSession s
 JOIN toeic.ExamVersion v ON v.Id=s.VersionId
 LEFT JOIN toeic.Attempt a ON a.SessionId=s.Id AND a.Status=''Submitted''
 GROUP BY s.Id,s.VersionId;');

EXEC(N'CREATE OR ALTER VIEW toeic.vQuestionStatistics AS
 SELECT a.SessionId,aq.VersionId,aq.QuestionId,q.OriginalNumber,
 COUNT(*) SeenCount,
 SUM(CASE WHEN r.ChoiceId=k.CorrectChoiceId THEN 1 ELSE 0 END) CorrectCount,
 SUM(CASE WHEN r.ChoiceId IS NOT NULL AND r.ChoiceId<>k.CorrectChoiceId THEN 1 ELSE 0 END) WrongCount,
 SUM(CASE WHEN r.ChoiceId IS NULL THEN 1 ELSE 0 END) SkippedCount
 FROM toeic.Attempt a JOIN toeic.AttemptQuestion aq ON aq.AttemptId=a.Id
 JOIN toeic.Question q ON q.Id=aq.QuestionId
 JOIN toeic.AnswerKey k ON k.QuestionId=q.Id
 LEFT JOIN toeic.Response r ON r.AttemptId=aq.AttemptId AND r.QuestionId=aq.QuestionId
 WHERE a.Status=''Submitted''
 GROUP BY a.SessionId,aq.VersionId,aq.QuestionId,q.OriginalNumber;');
INSERT #ToeicSetupSuccess VALUES(1);
COMMIT TRANSACTION;
PRINT N'SETUP OK: bảng, procedures và views đã sẵn sàng.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
-- Chỉ chạy test nếu phần setup ở trên thành công trên cùng kết nối.
IF OBJECT_ID('tempdb..#ToeicSetupSuccess') IS NULL
BEGIN
    THROW 51103, N'Chưa chạy setup thành công. Hãy chạy toàn bộ file.', 1;
END;
IF NOT EXISTS(SELECT 1 FROM #ToeicSetupSuccess WHERE Succeeded=1)
BEGIN
    THROW 51104, N'Setup thất bại. Xem lỗi trước đó, chưa chạy test.', 1;
END;
/*
Test fixture NHỎ, không phải đề Reading chính thức.
Không gọi PublishVersion vì fixture chỉ có 4 câu.
Toàn bộ dữ liệu test ROLLBACK; identity counters có thể tăng.
Chỉ chạy sau 01 và 02. Không dùng fixture này thay Word 100 câu.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRAN;
DECLARE @Suffix nvarchar(36)=CONVERT(nvarchar(36),NEWID());
INSERT toeic.Person(AccountId,FullName) VALUES(N'test-teacher-'+@Suffix,N'Test teacher');
DECLARE @Teacher bigint=SCOPE_IDENTITY();
INSERT toeic.Person(AccountId,FullName) VALUES(N'test-student1-'+@Suffix,N'Test student 1');
DECLARE @Student1 bigint=SCOPE_IDENTITY();
INSERT toeic.Person(AccountId,FullName) VALUES(N'test-student2-'+@Suffix,N'Test student 2');
DECLARE @Student2 bigint=SCOPE_IDENTITY();
INSERT toeic.Exam(Title,OwnerId) VALUES(N'ROLLBACK TEST ONLY',@Teacher);
DECLARE @Exam bigint=SCOPE_IDENTITY();
INSERT toeic.ExamVersion(ExamId,VersionNo,ExpectedQuestions,Status) VALUES(@Exam,1,4,'Published');
DECLARE @Version bigint=SCOPE_IDENTITY();
DECLARE @Number int=101,@Block bigint;
WHILE @Number<=104
BEGIN
 INSERT toeic.QuestionBlock(VersionId,PartNo,OriginalOrder) VALUES(@Version,5,@Number-100);
 SET @Block=SCOPE_IDENTITY();
 INSERT toeic.Question(VersionId,BlockId,OriginalNumber,OrderInBlock,Stem,Hint,Explanation)
 VALUES(@Version,@Block,@Number,1,N'Test question',N'Test hint',N'Test explanation');
 SET @Number+=1;
END;
INSERT toeic.Choice(QuestionId,OriginalLabel,Content)
SELECT q.Id,l.Label,N'Test '+l.Label FROM toeic.Question q
CROSS JOIN (VALUES('A'),('B'),('C'),('D')) l(Label) WHERE q.VersionId=@Version;
INSERT toeic.AnswerKey(QuestionId,CorrectChoiceId)
SELECT c.QuestionId,c.Id FROM toeic.Choice c JOIN toeic.Question q ON q.Id=c.QuestionId
WHERE q.VersionId=@Version AND c.OriginalLabel='B';
DECLARE @Now datetime2(3)=SYSUTCDATETIME();
INSERT toeic.ExamSession(VersionId,TeacherId,Name,Shift,StartsAt,EntryClosesAt,EndsAt,Status)
VALUES(@Version,@Teacher,N'Test session','Other',DATEADD(minute,-1,@Now),
DATEADD(minute,10,@Now),DATEADD(minute,75,@Now),'Published');
DECLARE @Session bigint=SCOPE_IDENTITY();
INSERT toeic.SessionCandidate VALUES(@Session,@Student1),(@Session,@Student2);
DECLARE @A1 uniqueidentifier=NEWID(),@A2 uniqueidentifier=NEWID(),@Lease uniqueidentifier=NEWID();
INSERT toeic.Attempt(Id,SessionId,VersionId,PersonId,StartedAt,DeadlineAt,ActiveLeaseId)
VALUES(@A1,@Session,@Version,@Student1,@Now,DATEADD(minute,75,@Now),@Lease),
(@A2,@Session,@Version,@Student2,@Now,DATEADD(minute,75,@Now),NEWID());
INSERT toeic.AttemptQuestion(AttemptId,VersionId,QuestionId,DisplayOrder)
SELECT a.Id,@Version,q.Id,q.OriginalNumber-100
FROM toeic.Attempt a CROSS JOIN toeic.Question q
WHERE a.Id IN(@A1,@A2) AND q.VersionId=@Version;
-- Hoán vị nhãn: B đúng hiển thị D. Chấm phải dùng ChoiceId.
INSERT toeic.AttemptChoice(AttemptId,QuestionId,ChoiceId,DisplayLabel)
SELECT aq.AttemptId,aq.QuestionId,c.Id,
CASE c.OriginalLabel WHEN 'B' THEN 'D' WHEN 'D' THEN 'B' ELSE c.OriginalLabel END
FROM toeic.AttemptQuestion aq JOIN toeic.Choice c ON c.QuestionId=aq.QuestionId
WHERE aq.AttemptId IN(@A1,@A2);
DECLARE @Q1 bigint,@Q2 bigint,@C1 bigint,@C2 bigint;
SELECT @Q1=Id FROM toeic.Question WHERE VersionId=@Version AND OriginalNumber=101;
SELECT @Q2=Id FROM toeic.Question WHERE VersionId=@Version AND OriginalNumber=102;
SELECT @C1=Id FROM toeic.Choice WHERE QuestionId=@Q1 AND OriginalLabel='B';
SELECT @C2=Id FROM toeic.Choice WHERE QuestionId=@Q2 AND OriginalLabel='D';
EXEC toeic.SaveResponse @A1,@Student1,@Lease,@Q1,@C1,0,2;
-- Request revision cũ không được xóa đáp án revision 2.
EXEC toeic.SaveResponse @A1,@Student1,@Lease,@Q1,NULL,0,1;
IF NOT EXISTS(SELECT 1 FROM toeic.Response WHERE AttemptId=@A1 AND QuestionId=@Q1 AND ChoiceId=@C1 AND Revision=2)
 THROW 51901,N'FAIL: revision cũ ghi đè.',1;
EXEC toeic.SaveResponse @A1,@Student1,@Lease,@Q2,@C2,0,1;
EXEC toeic.SubmitAttempt @A1,@Student1;
EXEC toeic.SubmitAttempt @A1,@Student1;
IF NOT EXISTS(SELECT 1 FROM toeic.Attempt WHERE Id=@A1 AND CorrectCount=1 AND WrongCount=1 AND SkippedCount=2)
 THROW 51902,N'FAIL: nộp một phần hoặc hoán vị chấm sai.',1;
EXEC toeic.SubmitAttempt @A2,@Student2;
IF NOT EXISTS(SELECT 1 FROM toeic.Attempt WHERE Id=@A2 AND CorrectCount=0 AND WrongCount=0 AND SkippedCount=4)
 THROW 51903,N'FAIL: nộp 0 câu.',1;
IF NOT EXISTS(SELECT 1 FROM toeic.vSessionStatistics WHERE SessionId=@Session AND SubmittedAttempts=2 AND AverageCorrect=0.50)
 THROW 51904,N'FAIL: thống kê ca.',1;
IF NOT EXISTS(SELECT 1 FROM toeic.vQuestionStatistics WHERE SessionId=@Session AND QuestionId=@Q2 AND WrongCount=1 AND SkippedCount=1)
 THROW 51905,N'FAIL: sai/bỏ qua bị gộp.',1;
ROLLBACK;
PRINT N'PASS: partial submit, zero-answer submit, idempotent submit, shuffled choice, stale revision, statistics. Test data rolled back.';
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
END CATCH;
GO
-- Xem danh sách bảng sau khi hoàn tất.
IF OBJECT_ID('tempdb..#ToeicSetupSuccess') IS NOT NULL
BEGIN
    SELECT SCHEMA_NAME(schema_id) AS SchemaName, name AS TableName
    FROM sys.tables WHERE schema_id=SCHEMA_ID(N'toeic') ORDER BY name;
END;
GO
