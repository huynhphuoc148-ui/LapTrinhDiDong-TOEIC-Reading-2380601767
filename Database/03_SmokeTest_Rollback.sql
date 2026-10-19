USE ToeicExamDesignDb;
GO
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
