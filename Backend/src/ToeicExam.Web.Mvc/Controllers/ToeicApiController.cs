using System;
using System.Threading.Tasks;
using Abp.Authorization;
using Abp.UI;
using Abp.Web.Models;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using ToeicExam.Controllers;
using ToeicExam.Web.Toeic;

namespace ToeicExam.Web.Controllers;

[Route("api/toeic")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
[IgnoreAntiforgeryToken] // Bearer-only controller; cookie authentication cannot authorize these endpoints.
[DontWrapResult]
public sealed class ToeicApiController : ToeicExamControllerBase
{
    private readonly IConfiguration _config;
    private readonly IPermissionChecker _permissions;
    public ToeicApiController(IConfiguration config, IPermissionChecker permissions) { _config = config; _permissions = permissions; }
    private async Task<IActionResult> Run(bool teacher, Func<ToeicStore, long, Task<object>> action, Func<Task> beforeDatabase = null)
    {
        if (!AbpSession.UserId.HasValue || AbpSession.TenantId.HasValue)
            return StatusCode(403, new { message = "Module thi dùng tài khoản Host. Khi đăng nhập web, để trống tên tenant." });
        if (teacher && !await _permissions.IsGrantedAsync("Pages.Toeic.Manage"))
            return StatusCode(403, new { message = "Bạn chưa có quyền quản lý TOEIC." });
        try
        {
            if (beforeDatabase != null) await beforeDatabase();
            await using var db = new ToeicStore(_config);
            await db.Open();
            var person = await db.Person(AbpSession.UserId.Value);
            return Ok(await action(db, person));
        }
        catch (UserFriendlyException ex) { return BadRequest(new { message = ex.Message }); }
        catch (SqlException ex) when (ex.Number >= 51000 && ex.Number < 52000) { return BadRequest(new { message = ex.Message }); }
        catch (SqlException ex)
        {
            Logger.Error("TOEIC database request failed", ex);
            return StatusCode(503, new { message = "Không truy cập được dữ liệu TOEIC. Kiểm tra connection string, bảng toeic và log backend." });
        }
    }
    [HttpGet("me")]
    public Task<IActionResult> Me() => Run(false, async (db, p) => new { personId = p, canManage = await _permissions.IsGrantedAsync("Pages.Toeic.Manage") });
    [HttpGet("teacher/users")]
    public Task<IActionResult> Users() => Run(true, (db, p) => db.Students());
    [HttpGet("teacher/exams")]
    public Task<IActionResult> Exams() => Run(true, (db, p) => db.Exams(p));
    [HttpPost("teacher/exams"), RequestSizeLimit(4_000_000)]
    public Task<IActionResult> CreateExam([FromBody] ExamInput input) => Run(true, async (db, p) => new { id = await db.CreateExam(p, input) });
    [HttpPost("teacher/exams/import")]
    [RequestSizeLimit(WordExamImporter.MaxDocumentBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = WordExamImporter.MaxDocumentBytes)]
    public Task<IActionResult> ImportExam([FromForm] IFormFile file)
    {
        ExamInput imported = null;
        return Run(true,
            async (db, person) => new { id = await db.CreateExam(person, imported) },
            async () =>
            {
                if (file == null || file.Length == 0) throw new UserFriendlyException("Chọn một file DOCX trước khi nhập.");
                if (file.Length > WordExamImporter.MaxDocumentBytes) throw new UserFriendlyException("File DOCX vượt quá giới hạn 40 MB.");
                if (!string.Equals(System.IO.Path.GetExtension(file.FileName), ".docx", StringComparison.OrdinalIgnoreCase))
                    throw new UserFriendlyException("Chỉ nhận file .docx; không nhận .doc, .pdf hoặc file đổi đuôi.");
                await using var stream = file.OpenReadStream();
                imported = WordExamImporter.Import(stream);
            });
    }
    [HttpGet("teacher/exams/{id:long}/draft")]
    public Task<IActionResult> Draft(long id) => Run(true, async (db, person) => await db.Draft(person, id));
    [HttpPut("teacher/exams/{id:long}/draft"), RequestSizeLimit(20_000_000)]
    public Task<IActionResult> UpdateDraft(long id, [FromBody] ExamInput input) =>
        Run(true, async (db, person) => new { id = await db.UpdateDraft(person, id, input) });
    [HttpPost("teacher/exams/{id:long}/publish")]
    public Task<IActionResult> Publish(long id) => Run(true, async (db, p) => { await db.Publish(p, id); return new { published = true }; });
    [HttpGet("teacher/sessions")]
    public Task<IActionResult> TeacherSessions() => Run(true, (db, p) => db.Sessions(p, true));
    [HttpPost("teacher/sessions")]
    public Task<IActionResult> CreateSession([FromBody] SessionInput input) => Run(true, async (db, p) => new { id = await db.CreateSession(p, input) });
    [HttpPost("teacher/sessions/{id:long}/release")]
    public Task<IActionResult> Release(long id) => Run(true, async (db, p) =>
    {
        var rows = await db.Query("UPDATE toeic.ExamSession SET ScoreReleaseAt=SYSUTCDATETIME() OUTPUT inserted.Id WHERE Id=@s AND TeacherId=@p", ("@s", id), ("@p", p));
        if (rows.Count != 1) throw new UserFriendlyException("Không có quyền với ca thi.");
        return new { released = true };
    });
    [HttpGet("teacher/exams/{id:long}/statistics")]
    public Task<IActionResult> ExamStatistics(long id) => Run(true, (db, p) => db.ExamStatistics(p, id));
    [HttpGet("teacher/sessions/{id:long}/statistics")]
    public Task<IActionResult> Statistics(long id) => Run(true, (db, p) => db.Statistics(p, id));
    [HttpGet("sessions")]
    public Task<IActionResult> Sessions() => Run(false, (db, p) => db.Sessions(p, false));
    [HttpPost("sessions/{id:long}/start")]
    public Task<IActionResult> Start(long id) => Run(false, async (db, p) => await db.Attempt(p, await db.Start(p, id)));
    [HttpGet("attempts/{id:guid}")]
    public Task<IActionResult> Attempt(Guid id) => Run(false, (db, p) => db.Attempt(p, id));
    [HttpPost("attempts/{id:guid}/answers")]
    public Task<IActionResult> Save(Guid id, [FromBody] SaveInput input) => Run(false, (db, p) => db.Save(p, id, input));
    [HttpPost("attempts/{id:guid}/submit")]
    public Task<IActionResult> Submit(Guid id) => Run(false, async (db, p) => { await db.Submit(p, id); return await db.Attempt(p, id); });
}
