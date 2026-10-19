<#
TOEIC Classroom — bản nối API thật từ kiemtragk.zip.
Đọc mã các file bên dưới trước khi chạy nếu muốn. Không cần giải nén ZIP.
Chỉ cập nhật mã nguồn, sao lưu trước khi ghi, KHÔNG chạy SQL/migration/build tự động.
Database mặc định: ToeicExamDesignDb; server và cách xác thực giữ từ cấu hình của bạn.
Ví dụ: powershell -NoProfile -ExecutionPolicy Bypass -File .\CapNhat_TOEIC.ps1 -ProjectRoot .
#>
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$DatabaseName = 'ToeicExamDesignDb',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml')) -or !(Test-Path -LiteralPath (Join-Path $root 'Backend/ToeicExam.sln'))) {
    throw 'Chọn đúng thư mục kiemtragk có pubspec.yaml và Backend/ToeicExam.sln.'
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$files = [ordered]@{}

# FILE: Backend/src/ToeicExam.Core/Authorization/ToeicExamAuthorizationProvider.cs
$files['Backend/src/ToeicExam.Core/Authorization/ToeicExamAuthorizationProvider.cs'] = @'
using Abp.Authorization;
using Abp.Localization;
using Abp.MultiTenancy;

namespace ToeicExam.Authorization;

public class ToeicExamAuthorizationProvider : AuthorizationProvider
{
    public override void SetPermissions(IPermissionDefinitionContext context)
    {
        context.CreatePermission("Pages.Toeic.Manage", new FixedLocalizableString("Quản lý đề và ca thi TOEIC"), multiTenancySides: MultiTenancySides.Host);
        context.CreatePermission(PermissionNames.Pages_Users, L("Users"));
        context.CreatePermission(PermissionNames.Pages_Users_Activation, L("UsersActivation"));
        context.CreatePermission(PermissionNames.Pages_Roles, L("Roles"));
        context.CreatePermission(PermissionNames.Pages_Tenants, L("Tenants"), multiTenancySides: MultiTenancySides.Host);
    }

    private static ILocalizableString L(string name)
    {
        return new LocalizableString(name, ToeicExamConsts.LocalizationSourceName);
    }
}
'@

# FILE: Backend/src/ToeicExam.EntityFrameworkCore/EntityFrameworkCore/Seed/Host/HostRoleAndUserCreator.cs
$files['Backend/src/ToeicExam.EntityFrameworkCore/EntityFrameworkCore/Seed/Host/HostRoleAndUserCreator.cs'] = @'
using Abp.Authorization;
using Abp.Authorization.Roles;
using Abp.Authorization.Users;
using Abp.MultiTenancy;
using ToeicExam.Authorization;
using ToeicExam.Authorization.Roles;
using ToeicExam.Authorization.Users;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using System.Linq;

namespace ToeicExam.EntityFrameworkCore.Seed.Host;

public class HostRoleAndUserCreator
{
    private readonly ToeicExamDbContext _context;

    public HostRoleAndUserCreator(ToeicExamDbContext context)
    {
        _context = context;
    }

    public void Create()
    {
        CreateHostRoleAndUsers();
    }

    private void CreateHostRoleAndUsers()
    {
        // Admin role for host

        var adminRoleForHost = _context.Roles.IgnoreQueryFilters().FirstOrDefault(r => r.TenantId == null && r.Name == StaticRoleNames.Host.Admin);
        if (adminRoleForHost == null)
        {
            adminRoleForHost = _context.Roles.Add(new Role(null, StaticRoleNames.Host.Admin, StaticRoleNames.Host.Admin) { IsStatic = true, IsDefault = true }).Entity;
            _context.SaveChanges();
        }

        // Students must never inherit the administrator role by default.
        adminRoleForHost.IsDefault = false;
        if (!_context.Roles.IgnoreQueryFilters().Any(r => r.TenantId == null && r.Name == "Student"))
            _context.Roles.Add(new Role(null, "Student", "Sinh viên") { IsDefault = true });
        _context.SaveChanges();

        // Grant all permissions to admin role for host

        var grantedPermissions = _context.Permissions.IgnoreQueryFilters()
            .OfType<RolePermissionSetting>()
            .Where(p => p.TenantId == null && p.RoleId == adminRoleForHost.Id)
            .Select(p => p.Name)
            .ToList();

        var permissions = PermissionFinder
            .GetAllPermissions(new ToeicExamAuthorizationProvider())
            .Where(p => p.MultiTenancySides.HasFlag(MultiTenancySides.Host) &&
                        !grantedPermissions.Contains(p.Name))
            .ToList();

        if (permissions.Any())
        {
            _context.Permissions.AddRange(
                permissions.Select(permission => new RolePermissionSetting
                {
                    TenantId = null,
                    Name = permission.Name,
                    IsGranted = true,
                    RoleId = adminRoleForHost.Id
                })
            );
            _context.SaveChanges();
        }

        // Admin user for host

        var adminUserForHost = _context.Users.IgnoreQueryFilters().FirstOrDefault(u => u.TenantId == null && u.UserName == AbpUserBase.AdminUserName);
        if (adminUserForHost == null)
        {
            var user = new User
            {
                TenantId = null,
                UserName = AbpUserBase.AdminUserName,
                Name = "admin",
                Surname = "admin",
                EmailAddress = "admin@aspnetboilerplate.com",
                IsEmailConfirmed = true,
                IsActive = true
            };

            user.Password = new PasswordHasher<User>(new OptionsWrapper<PasswordHasherOptions>(new PasswordHasherOptions())).HashPassword(user, "123qwe");
            user.SetNormalizedNames();

            adminUserForHost = _context.Users.Add(user).Entity;
            _context.SaveChanges();

            // Assign Admin role to admin user
            _context.UserRoles.Add(new UserRole(null, adminUserForHost.Id, adminRoleForHost.Id));
            _context.SaveChanges();

            _context.SaveChanges();
        }
    }
}
'@

# FILE: Backend/src/ToeicExam.Web.Core/Controllers/TokenAuthController.cs
$files['Backend/src/ToeicExam.Web.Core/Controllers/TokenAuthController.cs'] = @'
using Abp.Authorization;
using Abp.Authorization.Users;
using Abp.MultiTenancy;
using Abp.Runtime.Security;
using ToeicExam.Authentication.JwtBearer;
using ToeicExam.Authorization;
using ToeicExam.Authorization.Users;
using ToeicExam.Models.TokenAuth;
using ToeicExam.MultiTenancy;
using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace ToeicExam.Controllers
{
    [Route("api/[controller]/[action]")]
    public class TokenAuthController : ToeicExamControllerBase
    {
        private readonly LogInManager _logInManager;
        private readonly ITenantCache _tenantCache;
        private readonly AbpLoginResultTypeHelper _abpLoginResultTypeHelper;
        private readonly TokenAuthConfiguration _configuration;

        public TokenAuthController(
            LogInManager logInManager,
            ITenantCache tenantCache,
            AbpLoginResultTypeHelper abpLoginResultTypeHelper,
            TokenAuthConfiguration configuration)
        {
            _logInManager = logInManager;
            _tenantCache = tenantCache;
            _abpLoginResultTypeHelper = abpLoginResultTypeHelper;
            _configuration = configuration;
        }

        [HttpPost]
        [IgnoreAntiforgeryToken]
        public async Task<AuthenticateResultModel> Authenticate([FromBody] AuthenticateModel model)
        {
            var loginResult = await GetLoginResultAsync(
                model.UserNameOrEmailAddress,
                model.Password,
                GetTenancyNameOrNull()
            );

            var accessToken = CreateAccessToken(CreateJwtClaims(loginResult.Identity));

            return new AuthenticateResultModel
            {
                AccessToken = accessToken,
                EncryptedAccessToken = GetEncryptedAccessToken(accessToken),
                ExpireInSeconds = (int)_configuration.Expiration.TotalSeconds,
                UserId = loginResult.User.Id
            };
        }

        private string GetTenancyNameOrNull()
        {
            if (!AbpSession.TenantId.HasValue)
            {
                return null;
            }

            return _tenantCache.GetOrNull(AbpSession.TenantId.Value)?.TenancyName;
        }

        private async Task<AbpLoginResult<Tenant, User>> GetLoginResultAsync(string usernameOrEmailAddress, string password, string tenancyName)
        {
            var loginResult = await _logInManager.LoginAsync(usernameOrEmailAddress, password, tenancyName);

            switch (loginResult.Result)
            {
                case AbpLoginResultType.Success:
                    return loginResult;
                default:
                    throw _abpLoginResultTypeHelper.CreateExceptionForFailedLoginAttempt(loginResult.Result, usernameOrEmailAddress, tenancyName);
            }
        }

        private string CreateAccessToken(IEnumerable<Claim> claims, TimeSpan? expiration = null)
        {
            var now = DateTime.UtcNow;

            var jwtSecurityToken = new JwtSecurityToken(
                issuer: _configuration.Issuer,
                audience: _configuration.Audience,
                claims: claims,
                notBefore: now,
                expires: now.Add(expiration ?? _configuration.Expiration),
                signingCredentials: _configuration.SigningCredentials
            );

            return new JwtSecurityTokenHandler().WriteToken(jwtSecurityToken);
        }

        private static List<Claim> CreateJwtClaims(ClaimsIdentity identity)
        {
            var claims = identity.Claims.ToList();
            var nameIdClaim = claims.First(c => c.Type == ClaimTypes.NameIdentifier);

            // Specifically add the jti (random nonce), iat (issued timestamp), and sub (subject/user) claims.
            claims.AddRange(new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub, nameIdClaim.Value),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(JwtRegisteredClaimNames.Iat, DateTimeOffset.Now.ToUnixTimeSeconds().ToString(), ClaimValueTypes.Integer64)
            });

            return claims;
        }

        private string GetEncryptedAccessToken(string accessToken)
        {
            return SimpleStringCipher.Instance.Encrypt(accessToken);
        }
    }
}
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Controllers/ToeicApiController.cs
$files['Backend/src/ToeicExam.Web.Mvc/Controllers/ToeicApiController.cs'] = @'
using System;
using System.Threading.Tasks;
using Abp.Authorization;
using Abp.UI;
using Abp.Web.Models;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
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
    private async Task<IActionResult> Run(bool teacher, Func<ToeicStore, long, Task<object>> action)
    {
        if (!AbpSession.UserId.HasValue || AbpSession.TenantId.HasValue)
            return StatusCode(403, new { message = "Module thi dùng tài khoản Host. Khi đăng nhập web, để trống tên tenant." });
        if (teacher && !await _permissions.IsGrantedAsync("Pages.Toeic.Manage"))
            return StatusCode(403, new { message = "Bạn chưa có quyền quản lý TOEIC." });
        try
        {
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
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Properties/launchSettings.json
$files['Backend/src/ToeicExam.Web.Mvc/Properties/launchSettings.json'] = @'
{
  "iisSettings": {
    "windowsAuthentication": false,
    "anonymousAuthentication": true,
    "iisExpress": {
      "applicationUrl": "https://localhost:44312/",
      "sslPort": 44312
    }
  },
  "profiles": {
    "IIS Express": {
      "commandName": "IISExpress",
      "launchBrowser": true,
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "ToeicExam.Web": {
      "commandName": "Project",
      "launchBrowser": true,
      "applicationUrl": "https://localhost:44312",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "Toeic.Local": {
      "commandName": "Project",
      "launchBrowser": false,
      "applicationUrl": "http://localhost:5000",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Startup/Startup.cs
$files['Backend/src/ToeicExam.Web.Mvc/Startup/Startup.cs'] = @'
using Abp.AspNetCore;
using Abp.AspNetCore.Mvc.Antiforgery;
using Abp.AspNetCore.SignalR.Hubs;
using Abp.Castle.Logging.Log4Net;
using ToeicExam.Authentication.JwtBearer;
using ToeicExam.Configuration;
using ToeicExam.Identity;
using ToeicExam.Web.Resources;
using Castle.Facilities.Logging;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.WebEncoders;
using System.Text.Encodings.Web;
using System.Text.Unicode;

namespace ToeicExam.Web.Startup;

public class Startup
{
    private readonly IWebHostEnvironment _hostingEnvironment;
    private readonly IConfigurationRoot _appConfiguration;

    public Startup(IWebHostEnvironment env)
    {
        _hostingEnvironment = env;
        _appConfiguration = env.GetAppConfiguration();
    }

    public void ConfigureServices(IServiceCollection services)
    {
        // MVC
        services.AddControllersWithViews(
                options =>
                {
                    options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());
                    options.Filters.Add(new AbpAutoValidateAntiforgeryTokenAttribute());
                }
            );

        IdentityRegistrar.Register(services);
        AuthConfigurer.Configure(services, _appConfiguration);

        services.Configure<WebEncoderOptions>(options =>
        {
            options.TextEncoderSettings = new TextEncoderSettings(UnicodeRanges.All);
        });

        services.AddScoped<IWebResourceManager, WebResourceManager>();

        services.AddSignalR();
        if (_hostingEnvironment.IsDevelopment())
            services.AddCors(options => options.AddPolicy("ToeicLocal", policy => policy
                .WithOrigins("http://localhost:5173", "http://127.0.0.1:5173")
                .AllowAnyHeader().AllowAnyMethod()));
        services.AddHostedService<ToeicExam.Web.Toeic.ToeicTimeoutWorker>();

        // Configure Abp and Dependency Injection
        services.AddAbpWithoutCreatingServiceProvider<ToeicExamWebMvcModule>(
            // Configure Log4Net logging
            options => options.IocManager.IocContainer.AddFacility<LoggingFacility>(
                f => f.UseAbpLog4Net().WithConfig(
                    _hostingEnvironment.IsDevelopment()
                        ? "log4net.config"
                        : "log4net.Production.config"
                    )
            )
        );
    }

    public void Configure(IApplicationBuilder app, IWebHostEnvironment env, ILoggerFactory loggerFactory)
    {
        app.UseAbp(); // Initializes ABP framework.

        if (env.IsDevelopment())
        {
            app.UseDeveloperExceptionPage();
        }
        else
        {
            app.UseExceptionHandler("/Error");
        }

        app.UseStaticFiles();

        app.UseRouting();
        if (env.IsDevelopment()) app.UseCors("ToeicLocal");

        app.UseAuthentication();

        app.UseJwtTokenMiddleware();

        app.UseAuthorization();

        app.UseEndpoints(endpoints =>
        {
            endpoints.MapHub<AbpCommonHub>("/signalr");
            endpoints.MapControllerRoute("default", "{controller=Home}/{action=Index}/{id?}");
            endpoints.MapControllerRoute("defaultWithArea", "{area}/{controller=Home}/{action=Index}/{id?}");
        });
    }
}
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicModels.cs
$files['Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicModels.cs'] = @'
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ToeicExam.Web.Toeic;

public sealed class ExamInput
{
    [Required, StringLength(250, MinimumLength = 1)] public string Title { get; set; }
    public List<BlockInput> Blocks { get; set; } = new();
}
public sealed class BlockInput
{
    public int Part { get; set; }
    public bool Shuffle { get; set; }
    public List<string> Passages { get; set; } = new();
    public List<QuestionInput> Questions { get; set; } = new();
}
public sealed class QuestionInput
{
    public int Number { get; set; }
    public string Stem { get; set; } = "";
    public string Hint { get; set; } = "";
    public string Explanation { get; set; } = "";
    public bool ShuffleOptions { get; set; }
    public string Answer { get; set; }
    public Dictionary<string, string> Choices { get; set; } = new();
}
public sealed class SessionInput
{
    public long VersionId { get; set; }
    [Required, StringLength(200)] public string Name { get; set; }
    public string Shift { get; set; } = "Morning";
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset EntryClosesAt { get; set; }
    public DateTimeOffset EndsAt { get; set; }
    public DateTimeOffset? ScoreReleaseAt { get; set; }
    public List<long> CandidateUserIds { get; set; } = new();
}
public sealed class SaveInput
{
    public Guid LeaseId { get; set; }
    public long QuestionId { get; set; }
    public long? ChoiceId { get; set; }
    public bool MarkedForReview { get; set; }
    public int Revision { get; set; }
}
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicStore.cs
$files['Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicStore.cs'] = @'
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Abp.UI;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace ToeicExam.Web.Toeic;

// The domain schema is single-tenant. Controllers explicitly restrict access to host users.
// All values are parameterized. No student-supplied person/account identifier is trusted.
public sealed class ToeicStore : IAsyncDisposable
{
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
        Require(exam != null && !string.IsNullOrWhiteSpace(exam.Title) && exam.Title.Length <= 250, "Tên đề không hợp lệ.");
        Require(exam.Blocks != null && exam.Blocks.Count > 0 && exam.Blocks.Count <= 100, "Cần từ 1 đến 100 nhóm.");
        var numbers = new HashSet<int>();
        foreach (var b in exam.Blocks)
        {
            Require(b != null && new[] { 5, 6, 7 }.Contains(b.Part), "Part chỉ nhận 5, 6, 7.");
            Require(b.Questions != null && b.Questions.Count > 0 && b.Questions.Count <= 100, "Nhóm thiếu câu hỏi.");
            Require(b.Passages != null && b.Passages.Count <= 10 && b.Passages.All(x => !string.IsNullOrWhiteSpace(x) && x.Length <= 100000), "Bài đọc rỗng hoặc quá dài.");
            Require(b.Part != 5 || b.Questions.Count == 1, "Part 5: mỗi nhóm phải có một câu.");
            Require(b.Part != 6 || b.Questions.Count == 4, "Part 6: mỗi nhóm phải có bốn câu.");
            Require(b.Part == 5 || b.Passages.Count > 0, "Part 6/7 cần bài đọc.");
            if (b.Part == 6)
            {
                var refs = System.Text.RegularExpressions.Regex.Matches(string.Join("\n", b.Passages), @"\{\{(\d+)\}\}");
                Require(refs.Count == b.Questions.Count && refs.Cast<System.Text.RegularExpressions.Match>().All(m => b.Questions.Any(q => q != null && q.Number.ToString() == m.Groups[1].Value)), "Part 6 có tham chiếu chỗ trống lạ hoặc trùng.");
            }
            foreach (var q in b.Questions)
            {
                Require(q != null, "Câu hỏi không được null.");
                var range = b.Part == 5 ? (101, 130) : b.Part == 6 ? (131, 146) : (147, 200);
                Require(q.Number >= range.Item1 && q.Number <= range.Item2 && numbers.Add(q.Number), "Số câu trùng hoặc không khớp Part: " + q.Number);
                Require(q.Stem != null && (b.Part == 6 || !string.IsNullOrWhiteSpace(q.Stem)) && q.Stem.Length <= 20000, "Thiếu nội dung câu " + q.Number);
                Require(!string.IsNullOrWhiteSpace(q.Hint) && !string.IsNullOrWhiteSpace(q.Explanation) && q.Hint.Length <= 20000 && q.Explanation.Length <= 20000, "Thiếu gợi ý/giải thích câu " + q.Number);
                Require(q.Choices != null && q.Choices.Count == 4 && new[] { "A", "B", "C", "D" }.All(k => q.Choices.ContainsKey(k) && !string.IsNullOrWhiteSpace(q.Choices[k]) && q.Choices[k].Length <= 20000), "Câu cần đúng bốn lựa chọn A/B/C/D: " + q.Number);
                Require(q.Answer != null && q.Choices.ContainsKey(q.Answer), "Đáp án sai định dạng: " + q.Number);
                if (b.Part == 6) Require(b.Passages.Sum(p => p.Split("{{" + q.Number + "}}", StringSplitOptions.None).Length - 1) == 1, "Part 6 cần đúng một chỗ trống {{" + q.Number + "}} trong bài đọc.");
            }
        }
        Require(numbers.Count == 100, "Đề Reading cần đủ 100 câu 101–200. Không nhập dữ liệu nếu chưa hợp lệ.");
    }
    public async Task<long> CreateExam(long person, ExamInput exam)
    {
        ValidateExam(exam);
        await Begin();
        var id = await Insert("INSERT toeic.Exam(Title,OwnerId) OUTPUT inserted.Id VALUES(@t,@p)", ("@t", exam.Title), ("@p", person));
        var version = await Insert("INSERT toeic.ExamVersion(ExamId,VersionNo) OUTPUT inserted.Id VALUES(@e,1)", ("@e", id));
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
        await Commit();
        return version;
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
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicTimeoutWorker.cs
$files['Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicTimeoutWorker.cs'] = @'
using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ToeicExam.Web.Toeic;

// Idempotent SQL submission also runs on read. If the process restarts, overdue rows are picked up again.
public sealed class ToeicTimeoutWorker : BackgroundService
{
    private readonly IConfiguration _config;
    private readonly ILogger<ToeicTimeoutWorker> _log;
    public ToeicTimeoutWorker(IConfiguration config, ILogger<ToeicTimeoutWorker> log) { _config = config; _log = log; }
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var db = new ToeicStore(_config);
                await db.Open();
                var rows = await db.Query(@"SELECT TOP(100) a.Id,a.PersonId FROM toeic.Attempt a JOIN toeic.ExamSession s ON s.Id=a.SessionId
WHERE a.Status='InProgress' AND a.DeadlineAt<=SYSUTCDATETIME() AND s.Status IN('Published','Closed') ORDER BY a.DeadlineAt");
                foreach (var row in rows)
                {
                    if (stoppingToken.IsCancellationRequested) break;
                    try { await db.Submit(Convert.ToInt64(row["personId"]), (Guid)row["id"]); }
                    catch (Exception ex) { _log.LogError(ex, "Could not submit expired TOEIC attempt {Attempt}", row["id"]); }
                }
            }
            catch (Exception ex) { _log.LogWarning(ex, "TOEIC timeout scan failed; retry in 15 seconds. Verify toeic schema setup."); }
            try { await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }
}
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/index.html
$files['Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/index.html'] = @'
<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TOEIC Classroom · Giảng viên</title>
<style>
:root{font:15px system-ui,sans-serif;color:#172b4d;background:#f5f7fc}*{box-sizing:border-box}body{margin:0}header{background:#1048b8;color:white;padding:22px max(24px,calc((100vw - 1160px)/2));display:flex;justify-content:space-between;align-items:center}header strong{font-size:22px}small{display:block;opacity:.8;margin-top:5px}main{max-width:1160px;margin:28px auto;padding:0 20px}section{background:white;border:1px solid #e4e9f2;border-radius:12px;padding:24px;margin-bottom:20px}h1{margin-top:0;font-size:25px}h2{font-size:20px;margin-top:0}input,select,textarea,button{font:inherit;border:1px solid #d0d5dd;border-radius:7px;padding:10px}input,select,textarea{width:100%;background:white}textarea{min-height:180px;font-family:monospace;font-size:13px}button{background:#155eef;color:white;border-color:#155eef;cursor:pointer}button.secondary{color:#155eef;background:#eef4ff}button:disabled{opacity:.5;cursor:wait}label{display:block;margin:12px 0 6px;font-weight:600}.row{display:grid;grid-template-columns:1fr 1fr;gap:18px}.hint{color:#667085;font-size:13px;line-height:1.6}.actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:15px}.card{padding:15px 0;border-top:1px solid #e4e9f2}.card strong{font-size:16px}.pill{display:inline-block;border-radius:5px;padding:4px 8px;font-size:12px;background:#eaf0ff;color:#155eef;margin:6px 4px 6px 0}#message{position:sticky;top:0;z-index:2;white-space:pre-wrap}#message:not(:empty){padding:15px;background:#fff1d6;color:#664100;border:1px solid #eac57b;border-radius:8px;margin-bottom:15px}pre{white-space:pre-wrap;overflow-wrap:anywhere}details{margin-top:12px}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:10px;border-bottom:1px solid #e4e9f2}.scroll{overflow:auto}#users{max-height:220px;overflow:auto;border:1px solid #e4e9f2;padding:8px}#users label{font-weight:400;display:flex;align-items:center;gap:8px;margin:6px}#users input{width:auto}#login{max-width:480px;margin:40px auto}.hidden{display:none!important}@media(max-width:700px){.row{grid-template-columns:1fr}section{padding:18px}header strong{font-size:17px}}
</style></head><body>
<header><div><strong>TOEIC CLASSROOM</strong><small>Đề Reading · Ca thi · Kết quả</small></div><button id="logout" class="hidden">Đăng xuất</button></header>
<main><div id="message" role="status"></div><section id="login"><h1>Đăng nhập giảng viên</h1><p class="hint">Dùng tài khoản Host có quyền “Quản lý đề và ca thi TOEIC”. Tài khoản sinh viên dùng app Flutter.</p><form id="loginForm"><label>Tên tài khoản</label><input id="username" autocomplete="username" required><label>Mật khẩu</label><input id="password" type="password" autocomplete="current-password" required><div class="actions"><button>Đăng nhập</button></div></form></section>
<div id="workspace" class="hidden"><h1>Quản lý thi TOEIC Reading</h1><p class="hint">Luồng dữ liệu thật dùng SQL Server. Trang này bổ sung chức năng để chạy thử; chưa phải bản chuyển đổi đầy đủ thiết kế Stitch.</p>
<div class="row"><section><h2>1. Chuẩn bị đề thi</h2><p class="hint">Bản này nhận JSON gồm 100 câu, 75 phút. Chỉnh nội dung trước khi lưu. Dữ liệu mẫu chỉ để kiểm tra hệ thống, không phải đề Reading v10. Import Word có ảnh sẽ được bổ sung riêng.</p><div class="actions"><button class="secondary" id="sample">Nạp mẫu kiểm thử 100 câu</button><button class="secondary" id="previewButton">Xem trước</button></div><label>JSON đề thi</label><textarea id="examJson" spellcheck="false" placeholder='{"title":"Reading Test","blocks":[]}'></textarea><div class="actions"><button id="createExam">Kiểm tra và lưu bản nháp</button></div><details><summary>Nội dung xem trước</summary><div id="preview"></div></details></section>
<section><h2>Đề đã lưu</h2><button class="secondary" id="refresh">Tải lại dữ liệu</button><div id="exams"></div></section></div>
<section><h2>2. Mở ca thi</h2><p class="hint">Thời gian nhập theo múi giờ máy tính; gửi server theo UTC. Tạo ca xong sinh viên được chỉ định sẽ thấy lịch. Để trống giờ công bố điểm nghĩa là chưa công bố.</p><form id="sessionForm"><div class="row"><div><label>Tên ca thi</label><input id="sessionName" maxlength="200" required placeholder="Reading · Ca sáng lớp ..."><label>Đề đã xuất bản</label><select id="version" required></select><label>Ca</label><select id="shift"><option value="Morning">Sáng</option><option value="Afternoon">Chiều</option><option value="Evening">Tối</option><option value="Other">Khác</option></select><label>Tài khoản được dự thi</label><div id="users"></div><p class="hint">Tạo tài khoản sinh viên ở <a href="/Users" target="_blank">trang Users của ABP</a>, với tài khoản Host. Không cấp quyền quản lý cho sinh viên.</p></div><div><label>Bắt đầu</label><input id="starts" type="datetime-local" required><label>Hạn vào thi</label><input id="entry" type="datetime-local" required><label>Kết thúc ca</label><input id="ends" type="datetime-local" required><label>Công bố điểm từ</label><input id="release" type="datetime-local"><p class="hint">Thời hạn mỗi bài = thời điểm sớm hơn giữa “bắt đầu làm + 75 phút” và “kết thúc ca”. Sinh viên được nộp dù chưa chọn đáp án nào.</p></div></div><div class="actions"><button>Tạo và mở lịch ca thi</button></div></form></section>
<section><h2>3. Lịch thi và thống kê</h2><div id="sessions"></div></section><section id="reportSection" class="hidden"><h2>Kết quả ca thi</h2><div id="report"></div></section></div></main>
<script>
'use strict';
let token = null;
const $ = id => document.getElementById(id);
const text = (tag, value, cls) => {const e=document.createElement(tag); e.textContent=value; if(cls)e.className=cls;return e;};
function tell(message){$('message').textContent=message;}
async function api(path,method='GET',body){
 const response=await fetch(path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},credentials:'omit',body:body===undefined?undefined:JSON.stringify(body)});
 let data;try{data=await response.json();}catch{throw Error('Backend không trả JSON. Kiểm tra địa chỉ và log chạy server.');}
 if(!response.ok||data.success===false)throw Error(data.message||data.error?.message||('Lỗi HTTP '+response.status));
 return data.__abp ? data.result : data;
}
async function run(action){try{tell('');await action();}catch(e){tell(e.message||String(e));}}
function date(v){return v?new Date(v).toLocaleString('vi-VN'):'Chưa công bố';}
function local(d){const x=new Date(d.getTime()-d.getTimezoneOffset()*60000);return x.toISOString().slice(0,16);}
$('loginForm').onsubmit=e=>{e.preventDefault();run(async()=>{
 const result=await api('/api/TokenAuth/Authenticate','POST',{userNameOrEmailAddress:$('username').value.trim(),password:$('password').value,rememberClient:false});
 token=result.accessToken;const me=await api('/api/toeic/me');if(!me.canManage){token=null;throw Error('Tài khoản này không có quyền quản lý TOEIC.');}
 $('password').value='';$('login').classList.add('hidden');$('workspace').classList.remove('hidden');$('logout').classList.remove('hidden');await load();
});};
$('logout').onclick=()=>{token=null;location.reload();};
async function load(){
 const [exams,users,sessions]=await Promise.all([api('/api/toeic/teacher/exams'),api('/api/toeic/teacher/users'),api('/api/toeic/teacher/sessions')]);
 $('exams').replaceChildren();$('version').replaceChildren();
 for(const e of exams){const card=text('div','','card');card.append(text('strong',e.title),text('div',`#${e.id} · ${e.status} · ${e.expectedQuestions} câu · ${e.durationMinutes} phút`,'hint'));
 if(e.status==='Draft'){const b=text('button','Xuất bản');b.onclick=()=>run(async()=>{b.disabled=true;try{await api(`/api/toeic/teacher/exams/${e.id}/publish`,'POST',{});await load();tell('Đã xuất bản. Nội dung đề được khóa.');}finally{b.disabled=false;}});card.append(b);}
 if(e.status==='Published'){const o=text('option',`${e.title} (#${e.id})`);o.value=e.id;$('version').append(o);}$('exams').append(card);}
 if(!exams.length)$('exams').append(text('p','Chưa có đề nào.','hint'));
 const selected=new Set([...$('users').querySelectorAll('input:checked')].map(x=>x.value));$('users').replaceChildren();
 for(const u of users){const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.value=u.id;c.checked=selected.has(String(u.id));l.append(c,document.createTextNode(`${u.userName} — ${u.surname} ${u.name}`));$('users').append(l);}
 $('sessions').replaceChildren();for(const s of sessions){const c=text('div','','card');c.append(text('strong',s.name),text('p',`${s.title} · ${s.shift} · ${s.status}`,'hint'),text('p',`${date(s.startsAt)} → ${date(s.endsAt)} | Hạn vào: ${date(s.entryClosesAt)}`,'hint'),text('span',`${s.submittedAttempts}/${s.candidateCount} đã nộp`,'pill'),text('span',`Trung bình: ${s.averageCorrect??'—'}/100`,'pill'));const b=text('button','Xem thống kê','secondary');b.onclick=()=>run(()=>report(s.id));c.append(b);const release=text('button','Công bố điểm ngay','secondary');release.onclick=()=>run(async()=>{if(!confirm('Công bố điểm các bài đã nộp của ca này?'))return;await api(`/api/toeic/teacher/sessions/${s.id}/release`,'POST',{});tell('Đã công bố điểm.');});c.append(release);$('sessions').append(c);}
 if(!sessions.length)$('sessions').append(text('p','Chưa có ca thi.','hint'));
}
$('refresh').onclick=()=>run(load);
$('sample').onclick=()=>run(async()=>{const r=await fetch('./sample-exam.json');$('examJson').value=JSON.stringify(await r.json(),null,2);tell('Đây là dữ liệu tự tạo để kiểm thử, không phải nội dung/đáp án bài thi của giảng viên.');});
$('previewButton').onclick=()=>run(async()=>{const e=JSON.parse($('examJson').value);$('preview').replaceChildren(text('h3',e.title));for(const b of e.blocks){$('preview').append(text('h4','Part '+b.part));for(const p of b.passages||[])$('preview').append(text('pre',p));for(const q of b.questions){$('preview').append(text('p',`${q.number}. ${q.stem}`));for(const [k,v]of Object.entries(q.choices))$('preview').append(text('div',`${k}. ${v}`));$('preview').append(text('p',`Đáp án ${q.answer} · ${q.explanation}`,'hint'));}}$('preview').parentElement.open=true;});
$('createExam').onclick=()=>run(async()=>{const b=$('createExam');b.disabled=true;try{const result=await api('/api/toeic/teacher/exams','POST',JSON.parse($('examJson').value));await load();tell('Đã lưu bản nháp #'+result.id+'. Kiểm tra trước khi xuất bản.');}finally{b.disabled=false;}});
$('sessionForm').onsubmit=e=>{e.preventDefault();run(async()=>{const ids=[...$('users').querySelectorAll('input:checked')].map(x=>Number(x.value));if(!ids.length)throw Error('Chọn ít nhất một tài khoản dự thi.');const button=e.target.querySelector('button');button.disabled=true;try{await api('/api/toeic/teacher/sessions','POST',{versionId:Number($('version').value),name:$('sessionName').value,shift:$('shift').value,startsAt:new Date($('starts').value).toISOString(),entryClosesAt:new Date($('entry').value).toISOString(),endsAt:new Date($('ends').value).toISOString(),scoreReleaseAt:$('release').value?new Date($('release').value).toISOString():null,candidateUserIds:ids});await load();tell('Đã tạo lịch. Sinh viên tải lại danh sách ca thi trong app.');}finally{button.disabled=false;}});};
async function report(id){const r=await api(`/api/toeic/teacher/sessions/${id}/statistics`);const root=$('report');root.replaceChildren(text('p',`Đã nộp: ${r.summary.submittedAttempts} · Trung bình: ${r.summary.averageCorrect??'—'}/100`));const t=document.createElement('table');const head=document.createElement('tr');for(const h of ['Sinh viên','Trạng thái','Đúng','Sai','Bỏ trống'])head.append(text('th',h));t.append(head);for(const a of r.attempts){const tr=document.createElement('tr');for(const v of [a.fullName,a.status,a.correctCount??'—',a.wrongCount??'—',a.skippedCount??'—'])tr.append(text('td',v));t.append(tr);}const scroll=text('div','','scroll');scroll.append(t);root.append(scroll,text('h3','Top 10 câu chọn sai'));for(const q of r.topWrong)root.append(text('p',`Câu ${q.originalNumber}: ${q.wrongCount} chọn sai / ${q.seenCount} bài; ${q.skippedCount} bỏ trống`));if(!r.topWrong.length)root.append(text('p','Chưa có câu bị chọn sai.'));$('reportSection').classList.remove('hidden');$('reportSection').scrollIntoView({behavior:'smooth'});}
const now=new Date();$('starts').value=local(new Date(now.getTime()-60000));$('entry').value=local(new Date(now.getTime()+30*60000));$('ends').value=local(new Date(now.getTime()+90*60000));$('release').value=local(now);
</script></body></html>
'@

# FILE: Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/sample-exam.json
$files['Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/sample-exam.json'] = @'
{
  "title": "DEMO kỹ thuật — 100 câu (không phải Reading v10)",
  "blocks": [
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 101,
          "stem": "[DEMO 101] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 102,
          "stem": "[DEMO 102] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 103,
          "stem": "[DEMO 103] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 104,
          "stem": "[DEMO 104] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 105,
          "stem": "[DEMO 105] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 106,
          "stem": "[DEMO 106] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 107,
          "stem": "[DEMO 107] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 108,
          "stem": "[DEMO 108] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 109,
          "stem": "[DEMO 109] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 110,
          "stem": "[DEMO 110] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 111,
          "stem": "[DEMO 111] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 112,
          "stem": "[DEMO 112] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 113,
          "stem": "[DEMO 113] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 114,
          "stem": "[DEMO 114] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 115,
          "stem": "[DEMO 115] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 116,
          "stem": "[DEMO 116] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 117,
          "stem": "[DEMO 117] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 118,
          "stem": "[DEMO 118] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 119,
          "stem": "[DEMO 119] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 120,
          "stem": "[DEMO 120] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 121,
          "stem": "[DEMO 121] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 122,
          "stem": "[DEMO 122] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 123,
          "stem": "[DEMO 123] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 124,
          "stem": "[DEMO 124] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 125,
          "stem": "[DEMO 125] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 126,
          "stem": "[DEMO 126] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 127,
          "stem": "[DEMO 127] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 128,
          "stem": "[DEMO 128] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 129,
          "stem": "[DEMO 129] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 5,
      "shuffle": true,
      "passages": [],
      "questions": [
        {
          "number": 130,
          "stem": "[DEMO 130] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 6,
      "shuffle": true,
      "passages": [
        "DEMO NOTICE — Technical test only.\nThe office {{131}} at 8 a.m.\nThe office {{132}} at 8 a.m.\nThe office {{133}} at 8 a.m.\nThe office {{134}} at 8 a.m."
      ],
      "questions": [
        {
          "number": 131,
          "stem": "Choose the correct verb for blank 131.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 132,
          "stem": "Choose the correct verb for blank 132.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 133,
          "stem": "Choose the correct verb for blank 133.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 134,
          "stem": "Choose the correct verb for blank 134.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 6,
      "shuffle": true,
      "passages": [
        "DEMO NOTICE — Technical test only.\nThe office {{135}} at 8 a.m.\nThe office {{136}} at 8 a.m.\nThe office {{137}} at 8 a.m.\nThe office {{138}} at 8 a.m."
      ],
      "questions": [
        {
          "number": 135,
          "stem": "Choose the correct verb for blank 135.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 136,
          "stem": "Choose the correct verb for blank 136.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 137,
          "stem": "Choose the correct verb for blank 137.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 138,
          "stem": "Choose the correct verb for blank 138.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 6,
      "shuffle": true,
      "passages": [
        "DEMO NOTICE — Technical test only.\nThe office {{139}} at 8 a.m.\nThe office {{140}} at 8 a.m.\nThe office {{141}} at 8 a.m.\nThe office {{142}} at 8 a.m."
      ],
      "questions": [
        {
          "number": 139,
          "stem": "Choose the correct verb for blank 139.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 140,
          "stem": "Choose the correct verb for blank 140.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 141,
          "stem": "Choose the correct verb for blank 141.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 142,
          "stem": "Choose the correct verb for blank 142.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 6,
      "shuffle": true,
      "passages": [
        "DEMO NOTICE — Technical test only.\nThe office {{143}} at 8 a.m.\nThe office {{144}} at 8 a.m.\nThe office {{145}} at 8 a.m.\nThe office {{146}} at 8 a.m."
      ],
      "questions": [
        {
          "number": 143,
          "stem": "Choose the correct verb for blank 143.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 144,
          "stem": "Choose the correct verb for blank 144.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 145,
          "stem": "Choose the correct verb for blank 145.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 146,
          "stem": "Choose the correct verb for blank 146.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 147,
          "stem": "[DEMO 147] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 148,
          "stem": "[DEMO 148] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 149,
          "stem": "[DEMO 149] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 150,
          "stem": "[DEMO 150] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 151,
          "stem": "[DEMO 151] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 152,
          "stem": "[DEMO 152] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 153,
          "stem": "[DEMO 153] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 154,
          "stem": "[DEMO 154] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 155,
          "stem": "[DEMO 155] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 156,
          "stem": "[DEMO 156] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 157,
          "stem": "[DEMO 157] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 158,
          "stem": "[DEMO 158] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 159,
          "stem": "[DEMO 159] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 160,
          "stem": "[DEMO 160] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 161,
          "stem": "[DEMO 161] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 162,
          "stem": "[DEMO 162] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 163,
          "stem": "[DEMO 163] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 164,
          "stem": "[DEMO 164] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 165,
          "stem": "[DEMO 165] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 166,
          "stem": "[DEMO 166] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 167,
          "stem": "[DEMO 167] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 168,
          "stem": "[DEMO 168] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 169,
          "stem": "[DEMO 169] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 170,
          "stem": "[DEMO 170] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 171,
          "stem": "[DEMO 171] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 172,
          "stem": "[DEMO 172] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 173,
          "stem": "[DEMO 173] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 174,
          "stem": "[DEMO 174] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 175,
          "stem": "[DEMO 175] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 176,
          "stem": "[DEMO 176] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 177,
          "stem": "[DEMO 177] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 178,
          "stem": "[DEMO 178] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 179,
          "stem": "[DEMO 179] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 180,
          "stem": "[DEMO 180] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 181,
          "stem": "[DEMO 181] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 182,
          "stem": "[DEMO 182] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 183,
          "stem": "[DEMO 183] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 184,
          "stem": "[DEMO 184] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 185,
          "stem": "[DEMO 185] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 186,
          "stem": "[DEMO 186] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 187,
          "stem": "[DEMO 187] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 188,
          "stem": "[DEMO 188] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 189,
          "stem": "[DEMO 189] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 190,
          "stem": "[DEMO 190] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 191,
          "stem": "[DEMO 191] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 192,
          "stem": "[DEMO 192] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 193,
          "stem": "[DEMO 193] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 194,
          "stem": "[DEMO 194] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 195,
          "stem": "[DEMO 195] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 196,
          "stem": "[DEMO 196] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 197,
          "stem": "[DEMO 197] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    },
    {
      "part": 7,
      "shuffle": true,
      "passages": [
        "DEMO EMAIL — Technical test only.\nThe office opens at 8 a.m. every weekday."
      ],
      "questions": [
        {
          "number": 198,
          "stem": "[DEMO 198] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 199,
          "stem": "[DEMO 199] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        },
        {
          "number": 200,
          "stem": "[DEMO 200] The office ____ at 8 a.m.",
          "hint": "The subject is singular.",
          "explanation": "The singular subject takes opens in the present simple.",
          "shuffleOptions": true,
          "answer": "B",
          "choices": {
            "A": "open",
            "B": "opens",
            "C": "opening",
            "D": "opened"
          }
        }
      ]
    }
  ]
}
'@

# FILE: Backend/test/ToeicExam.Web.Tests/ToeicValidationTests.cs
$files['Backend/test/ToeicExam.Web.Tests/ToeicValidationTests.cs'] = @'
using System.Collections.Generic;
using System.Linq;
using Abp.UI;
using ToeicExam.Web.Toeic;
using Xunit;

namespace ToeicExam.Web.Tests;

public class ToeicValidationTests
{
    private static ExamInput Valid()
    {
        QuestionInput Q(int n) => new() { Number=n, Stem="The office ____ at 8.", Hint="Singular", Explanation="Present simple", Answer="B",
            Choices=new Dictionary<string,string>{{"A","open"},{"B","opens"},{"C","opening"},{"D","opened"}} };
        var e = new ExamInput { Title="Test" };
        for(var n=101;n<=130;n++) e.Blocks.Add(new BlockInput {Part=5,Questions=new(){Q(n)}});
        for(var n=131;n<=146;n+=4) e.Blocks.Add(new BlockInput {Part=6,Passages=new(){string.Join(" ",Enumerable.Range(n,4).Select(i=>"{{"+i+"}}"))},Questions=Enumerable.Range(n,4).Select(Q).ToList()});
        e.Blocks.Add(new BlockInput {Part=7,Passages=new(){"A passage."},Questions=Enumerable.Range(147,54).Select(Q).ToList()});
        return e;
    }
    [Fact] public void Accepts_full_reading_exam() => ToeicStore.ValidateExam(Valid());
    [Fact] public void Rejects_duplicate_number() { var e=Valid();e.Blocks[1].Questions[0].Number=101;Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e)); }
    [Fact] public void Rejects_missing_choice() { var e=Valid();e.Blocks[0].Questions[0].Choices.Remove("D");Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e)); }
    [Fact] public void Rejects_unknown_answer() { var e=Valid();e.Blocks[0].Questions[0].Answer="E";Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e)); }
    [Fact] public void Rejects_missing_part6_blank() {var e=Valid();e.Blocks.First(b=>b.Part==6).Passages=new(){"No blanks."};Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e));}
    [Fact] public void Rejects_null_block() {var e=Valid();e.Blocks[0]=null;Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e));}
    [Fact] public void Rejects_incomplete_exam() {var e=Valid();e.Blocks.RemoveAt(0);Assert.Throws<UserFriendlyException>(()=>ToeicStore.ValidateExam(e));}
}
'@

# FILE: Database/03_SmokeTest_Rollback.sql
$files['Database/03_SmokeTest_Rollback.sql'] = @'
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
'@

# FILE: Database/TOEIC_ALL_IN_ONE.sql
$files['Database/TOEIC_ALL_IN_ONE.sql'] = @'
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
'@

# FILE: android/app/src/debug/AndroidManifest.xml
$files['android/app/src/debug/AndroidManifest.xml'] = @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. Specifically,
         the Flutter tool needs it to communicate with the running application
         to allow setting breakpoints, to provide hot reload, etc.
    -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true" />
</manifest>
'@

# FILE: android/app/src/main/AndroidManifest.xml
$files['android/app/src/main/AndroidManifest.xml'] = @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="kiemtragk"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
'@

# FILE: docs/HUONG_DAN_CHAY_TIEP.md
$files['docs/HUONG_DAN_CHAY_TIEP.md'] = @'
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
'@

# FILE: lib/main.dart
$files['lib/main.dart'] = @'
import 'package:flutter/material.dart';
import 'toeic/student_app.dart';

void main() => runApp(const ToeicStudentApp());
'@

# FILE: lib/toeic/student_app.dart
$files['lib/toeic/student_app.dart'] = @'
import 'dart:async';
import 'package:flutter/material.dart';
import 'toeic_api.dart';

const _blue = Color(0xFF155EEF);
const _bg = Color(0xFFF5F7FC);
String _error(Object e) => e.toString().replaceFirst('Exception: ', '');
String _date(dynamic value) {
  if (value == null) return 'Chưa công bố';
  final d = DateTime.parse(value.toString()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
String _shift(dynamic value) => switch(value) {
  'Morning' => 'Ca sáng', 'Afternoon' => 'Ca chiều', 'Evening' => 'Ca tối', _ => 'Ca khác',
};

class ToeicStudentApp extends StatelessWidget {
  const ToeicStudentApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOEIC Classroom', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: _bg,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white)),
    home: const _Login(),
  );
}

class _Login extends StatefulWidget {
  const _Login();
  @override State<_Login> createState() => _LoginState();
}
class _LoginState extends State<_Login> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _api = ToeicApi();
  bool _busy = false;
  String? _message;
  @override void dispose() { _username.dispose(); _password.dispose(); _api.dispose(); super.dispose(); }
  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Nhập tài khoản và mật khẩu.'); return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await _api.login(_username.text, _password.text);
      if (!mounted) return;
      _password.clear();
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _Sessions(api: _api)));
      _api.logout();
    } catch(e) { if(mounted) setState(() => _message = _error(e)); }
    finally { if(mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.school_rounded,size:56,color:_blue), const SizedBox(height:12),
          const Text('TOEIC CLASSROOM',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),const Text('Đăng nhập sinh viên',textAlign:TextAlign.center),const SizedBox(height:28),
          TextField(controller:_username,enabled:!_busy,autofillHints:const [AutofillHints.username],decoration:const InputDecoration(labelText:'Tên tài khoản')),
          const SizedBox(height:16),TextField(controller:_password,enabled:!_busy,obscureText:true,autofillHints:const [AutofillHints.password],onSubmitted:(_){if(!_busy)_login();},decoration:const InputDecoration(labelText:'Mật khẩu')),
          const SizedBox(height:20),if(_message!=null)_Notice(_message!),
          FilledButton(onPressed:_busy?null:_login,child:Padding(padding:const EdgeInsets.all(12),child:Text(_busy?'Đang xử lý…':'Đăng nhập'))),
          const SizedBox(height:16),const Text('Tài khoản do giảng viên cấp.\nNếu quên mật khẩu, liên hệ giảng viên.',textAlign:TextAlign.center),
        ],
      )),
    )),
  );
}

class _Sessions extends StatefulWidget {
  const _Sessions({required this.api});
  final ToeicApi api;
  @override State<_Sessions> createState() => _SessionsState();
}
class _SessionsState extends State<_Sessions> {
  List<dynamic> _sessions=[];
  bool _busy=true;
  String? _message;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    setState((){_busy=true;_message=null;});
    try{final data=await widget.api.sessions();if(mounted)setState(()=>_sessions=data);}
    catch(e){if(mounted)setState(()=>_message=_error(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _open(Map<String,dynamic> s) async {
    setState((){_busy=true;_message=null;});
    try{
      final data=s['attemptId']==null?await widget.api.start(s['id'] as int):await widget.api.attempt(s['attemptId'].toString());
      if(!mounted)return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>_Attempt(api:widget.api,data:data)));
      if(mounted)await _load();
    }catch(e){if(mounted)setState(()=>_message=_error(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Lịch thi của tôi'),actions:[IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh),tooltip:'Tải lại'),IconButton(onPressed:_busy?null:()=>Navigator.pop(context),icon:const Icon(Icons.logout),tooltip:'Đăng xuất')]),
    body:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('TOEIC Reading',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:8),
      const Text('Kiểm tra giờ mở ca và hạn vào thi. Bài làm được lưu trên server sau mỗi lần chọn.'),const SizedBox(height:16),
      if(_busy)const LinearProgressIndicator(),if(_message!=null)_Notice(_message!),
      if(!_busy&&_sessions.isEmpty&&_message==null)const _Notice('Bạn chưa được xếp vào ca thi nào. Liên hệ giảng viên rồi bấm tải lại.'),
      for(final raw in _sessions)Builder(builder:(context){
        final s=Map<String,dynamic>.from(raw as Map);
        final hasAttempt=s['attemptId']!=null;
        final submitted=s['attemptStatus']=='Submitted';
        return Card(margin:const EdgeInsets.only(bottom:14),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(s['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:19)),const SizedBox(height:5),Text(s['title'].toString()),
          Chip(label:Text('${_shift(s['shift'])} · ${submitted?'Đã nộp':s['status']=='Cancelled'?'Đã hủy':'100 câu / 75 phút'}')),
          Text('Bắt đầu: ${_date(s['startsAt'])}\nHạn vào: ${_date(s['entryClosesAt'])}\nKết thúc: ${_date(s['endsAt'])}'),
          const SizedBox(height:12),FilledButton.icon(onPressed:_busy||s['status']=='Cancelled'?null:()=>_open(s),icon:Icon(submitted?Icons.assessment:Icons.play_arrow),label:Text(submitted?'Xem kết quả':hasAttempt?'Tiếp tục bài thi':'Vào thi')),
        ])));
      }),
    ])),
  );
}

class _Attempt extends StatefulWidget {
  const _Attempt({required this.api,required this.data});
  final ToeicApi api;
  final Map<String,dynamic> data;
  @override State<_Attempt> createState()=>_AttemptState();
}
class _AttemptState extends State<_Attempt> with WidgetsBindingObserver {
  late Map<String,dynamic> _attempt;
  List<Map<String,dynamic>> _questions=[];
  final _elapsed=Stopwatch();
  Duration _initialRemaining=Duration.zero;
  Timer? _timer;
  int _index=0;
  bool _busy=false, _uncertain=false;
  String? _message;
  DateTime? _nextAutoRetry;
  String get _id=>_attempt['id'].toString();
  bool get _inProgress=>_attempt['status']=='InProgress'&&_attempt['sessionStatus']=='Published';
  Duration get _remaining=>_initialRemaining-_elapsed.elapsed;
  bool get _expired=>_remaining<=Duration.zero;
  bool get _canAnswer=>_inProgress&&!_busy&&!_uncertain&&!_expired;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_apply(widget.data);_timer=Timer.periodic(const Duration(seconds:1),(_){
    if(!mounted)return;
    setState((){});
    if(_inProgress&&_expired&&!_busy&&(_nextAutoRetry==null||DateTime.now().isAfter(_nextAutoRetry!)))_submit(automatic:true);
  });}
  void _apply(Map<String,dynamic> data){
    _attempt=Map<String,dynamic>.from(data['attempt'] as Map);
    _questions=(data['questions'] as List).map((q)=>Map<String,dynamic>.from(q as Map)).toList();
    _initialRemaining=DateTime.parse(_attempt['deadlineAt'].toString()).difference(DateTime.parse(_attempt['serverNow'].toString()));
    _elapsed..reset()..start();
    if(_index>=_questions.length)_index=0;
    _uncertain=false;
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_timer?.cancel();_elapsed.stop();super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed&&!_busy)_reload();}
  Future<void> _reload() async {
    setState((){_busy=true;_message=null;});
    try{final data=await widget.api.attempt(_id);if(mounted)setState(()=>_apply(data));}
    catch(e){if(mounted)setState(()=>_message=_error(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _save({int? choice,bool? marked})async{
    if(!_canAnswer)return;
    final q=_questions[_index];
    setState((){_busy=true;_message=null;});
    try{
      final response=await widget.api.save(_id,{
        'leaseId':_attempt['activeLeaseId'],'questionId':q['id'],
        'choiceId':marked==null?choice:q['choiceId'],
        'markedForReview':marked??q['markedForReview'],
        'revision':(q['revision'] as int)+1,
      });
      if(mounted)setState((){q['choiceId']=response['choiceId'];q['markedForReview']=response['markedForReview'];q['revision']=response['revision'];});
    }catch(e){if(mounted)setState((){_uncertain=true;_message='Chưa xác nhận lưu: ${_error(e)}\nBấm “Tải lại bài” để đối chiếu với server trước khi chọn tiếp.';});}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _submit({bool automatic=false})async{
    if(_busy)return;
    if(!automatic){
      if(_uncertain)return;
      final answered=_questions.where((q)=>q['choiceId']!=null).length;
      final accepted=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:const Text('Nộp bài thi?'),content:Text('Đã trả lời $answered/${_questions.length} câu.\nCòn ${_questions.length-answered} câu bỏ trống. Bạn vẫn có thể nộp; sau khi nộp không thể sửa.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Làm tiếp')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Nộp bài'))],
      ));
      if(accepted!=true||!mounted||_busy||!_inProgress)return;
    }
    setState((){_busy=true;_message=null;});
    try{final data=await widget.api.submit(_id);if(mounted)setState(()=>_apply(data));}
    catch(e){if(mounted)setState(()=>_message='Chưa xác nhận nộp bài: ${_error(e)}');_nextAutoRetry=DateTime.now().add(const Duration(seconds:10));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  String get _clock {final n=_remaining.inSeconds.clamp(0,99999);return '${(n~/60).toString().padLeft(2,'0')}:${(n%60).toString().padLeft(2,'0')}';}
  @override Widget build(BuildContext context){
    final done=_attempt['status']=='Submitted';
    return Scaffold(appBar:AppBar(title:Text(done?'Kết quả bài thi':'TOEIC Reading'),actions:[if(_inProgress)Padding(padding:const EdgeInsets.all(14),child:Text(_clock,style:TextStyle(fontWeight:FontWeight.bold,fontSize:20,color:_remaining.inMinutes<5?Colors.red:_blue)))]),
      body:ListView(padding:const EdgeInsets.all(18),children:[
        Text(_attempt['title'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        Text('${_attempt['name']} · Hạn nộp ${_date(_attempt['deadlineAt'])}'),
        if(_busy)const LinearProgressIndicator(),if(_message!=null)_Notice(_message!),
        Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:_busy?null:_reload,icon:const Icon(Icons.refresh),label:const Text('Tải lại bài'))),
        if(done)...[
          const Icon(Icons.check_circle,color:Colors.teal,size:64),const Center(child:Text('Bài thi đã được nộp',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))),
          const SizedBox(height:20),
          if(_attempt['correctCount']==null)_Notice('Điểm chưa được công bố. Thời gian dự kiến: ${_date(_attempt['scoreReleaseAt'])}.')
          else Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
            Text('${_attempt['correctCount']}/100',style:const TextStyle(fontSize:42,fontWeight:FontWeight.bold,color:_blue)),
            Text('Đúng: ${_attempt['correctCount']}  ·  Sai: ${_attempt['wrongCount']}  ·  Bỏ trống: ${_attempt['skippedCount']}'),
            const SizedBox(height:8),const Text('Số câu đúng Reading, chưa quy đổi sang thang điểm TOEIC.'),
          ]))),
          FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('Về danh sách ca thi')),
        ]else if(!_inProgress)const _Notice('Ca thi hoặc bài làm đã bị khóa. Liên hệ giảng viên.')
        else if(_questions.isNotEmpty)...[
          Text('Đã lưu ${_questions.where((q)=>q['choiceId']!=null).length}/${_questions.length} câu'),
          const SizedBox(height:10),Wrap(spacing:5,runSpacing:5,children:[for(var i=0;i<_questions.length;i++)SizedBox(width:48,height:38,child:OutlinedButton(
            style:OutlinedButton.styleFrom(padding:EdgeInsets.zero,backgroundColor:i==_index?_blue:_questions[i]['markedForReview']==true?Colors.amber.shade100:_questions[i]['choiceId']!=null?Colors.teal.shade50:Colors.white,foregroundColor:i==_index?Colors.white:_blue),
            onPressed:_busy?null:()=>setState(()=>_index=i),child:Text('${i+101}'),
          ))]),
          const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('Xanh nhạt: đã trả lời · Vàng: cần xem lại. Thứ tự câu có thể khác đề gốc.')),
          _questionCard(),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[TextButton(onPressed:_index==0||_busy?null:()=>setState(()=>_index--),child:const Text('Câu trước')),TextButton(onPressed:_index>=_questions.length-1||_busy?null:()=>setState(()=>_index++),child:const Text('Câu tiếp'))]),
          const SizedBox(height:16),FilledButton.icon(onPressed:_busy||_uncertain||_expired?null:()=>_submit(),icon:const Icon(Icons.send),label:const Padding(padding:EdgeInsets.all(12),child:Text('Nộp bài'))),
          if(_expired)const _Notice('Đã hết giờ. Đang xác nhận nộp bài với server; không thể đổi đáp án.'),
        ],
      ]),
    );
  }
  Widget _questionCard(){final q=_questions[_index];return Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('Part ${q['partNo']} · Câu ${_index+101} (gốc ${q['originalNumber']})',style:const TextStyle(fontWeight:FontWeight.bold,color:_blue)),
    for(final passage in q['passages'] as List)Container(margin:const EdgeInsets.symmetric(vertical:10),padding:const EdgeInsets.all(14),color:_bg,child:SelectableText(passage.toString())),
    const SizedBox(height:8),Text(q['stem'].toString(),style:const TextStyle(fontSize:18)),const SizedBox(height:12),
    for(final raw in q['choices'] as List)Builder(builder:(context){final c=Map<String,dynamic>.from(raw as Map);final selected=q['choiceId']==c['choiceId'];return Padding(padding:const EdgeInsets.only(bottom:8),child:OutlinedButton(
      style:OutlinedButton.styleFrom(alignment:Alignment.centerLeft,padding:const EdgeInsets.all(14),backgroundColor:selected?const Color(0xFFEAF0FF):Colors.white,side:BorderSide(color:selected?_blue:const Color(0xFFE4E9F2))),
      onPressed:_canAnswer?()=>_save(choice:c['choiceId'] as int):null,child:Text('${c['displayLabel']}. ${c['content']}'),
    ));}),
    Wrap(spacing:10,children:[TextButton(onPressed:_canAnswer&&q['choiceId']!=null?()=>_save():null,child:const Text('Bỏ chọn')),TextButton.icon(onPressed:_canAnswer?()=>_save(marked:q['markedForReview']!=true):null,icon:Icon(q['markedForReview']==true?Icons.flag:Icons.outlined_flag),label:Text(q['markedForReview']==true?'Bỏ đánh dấu':'Xem lại sau'))]),
    Text(_busy?'Đang lưu…':_uncertain?'Chưa xác nhận lưu':q['choiceId']==null?'Chưa chọn đáp án':'Đã lưu trên server',style:const TextStyle(fontSize:12,color:Colors.grey)),
  ])));}
}
class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;
  @override Widget build(BuildContext context)=>Container(width:double.infinity,margin:const EdgeInsets.symmetric(vertical:10),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFF2D7),borderRadius:BorderRadius.circular(8)),child:Text(message));
}
'@

# FILE: lib/toeic/toeic_api.dart
$files['lib/toeic/toeic_api.dart'] = @'
import 'dart:convert';
import 'package:http/http.dart' as http;

class ToeicApi {
  ToeicApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL', defaultValue: 'http://10.0.2.2:5000',
  );
  String? _token;
  void logout() => _token = null;
  void dispose() => _client.close();

  Future<dynamic> request(String path, {Object? body}) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    final response = await (body == null
        ? _client.get(url, headers: headers)
        : _client.post(url, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 30));
    dynamic value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Server không trả JSON (HTTP ${response.statusCode}). Kiểm tra API_BASE_URL và backend.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300 ||
        (value is Map && value['success'] == false)) {
      final message = value is Map
          ? value['message'] ?? (value['error'] is Map ? value['error']['message'] : null)
          : null;
      throw Exception(message ?? (response.statusCode == 401
          ? 'Phiên đăng nhập hết hạn. Quay về đăng nhập rồi mở lại ca thi.'
          : 'Yêu cầu thất bại (HTTP ${response.statusCode}).'));
    }
    if (value is Map && value['__abp'] == true) return value['result'];
    return value;
  }

  Future<void> login(String username, String password) async {
    _token = null;
    final result = await request('/api/TokenAuth/Authenticate', body: {
      'userNameOrEmailAddress': username.trim(),
      'password': password,
      'rememberClient': false,
    });
    _token = result['accessToken'] as String;
    try { await request('/api/toeic/me'); }
    catch (_) { _token = null; rethrow; }
  }
  Future<List<dynamic>> sessions() async =>
      List<dynamic>.from(await request('/api/toeic/sessions'));
  Future<Map<String, dynamic>> start(int id) async => Map<String, dynamic>.from(
      await request('/api/toeic/sessions/$id/start', body: {}));
  Future<Map<String, dynamic>> attempt(String id) async => Map<String, dynamic>.from(
      await request('/api/toeic/attempts/$id'));
  Future<Map<String, dynamic>> save(String id, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await request('/api/toeic/attempts/$id/answers', body: body));
  Future<Map<String, dynamic>> submit(String id) async => Map<String, dynamic>.from(
      await request('/api/toeic/attempts/$id/submit', body: {}));
}
'@

# FILE: test/toeic_api_test.dart
$files['test/toeic_api_test.dart'] = @'
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiemtragk/toeic/toeic_api.dart';

void main() {
  test('login unwraps ABP token and authenticates subsequent requests', () async {
    var sawBearer=false;
    final api=ToeicApi(client:MockClient((request) async {
      if(request.url.path.endsWith('Authenticate')) {
        expect(jsonDecode(request.body)['userNameOrEmailAddress'],'sv01');
        return http.Response(jsonEncode({'__abp':true,'success':true,'result':{'accessToken':'test-token'}}),200);
      }
      sawBearer=request.headers['Authorization']=='Bearer test-token';
      return http.Response('{"canManage":false}',200);
    }));
    await api.login(' sv01 ','password');
    expect(sawBearer,isTrue);api.dispose();
  });
  test('failed save is surfaced instead of reported as saved', () async {
    final api=ToeicApi(client:MockClient((_) async=>http.Response('{"message":"Bai da khoa"}',400)));
    await expectLater(api.save('a',{'revision':1}),throwsA(isA<Exception>()));api.dispose();
  });
  test('submit permits zero answers and sends no local score', () async {
    final api=ToeicApi(client:MockClient((request) async {
      expect(request.method,'POST');expect(jsonDecode(request.body),isEmpty);
      return http.Response('{"attempt":{"status":"Submitted","correctCount":0,"wrongCount":0,"skippedCount":100},"questions":[]}',200);
    }));
    final result=await api.submit('attempt-id');expect(result['attempt']['skippedCount'],100);api.dispose();
  });
}
'@

$expected = @{
    'Backend/src/ToeicExam.Core/Authorization/ToeicExamAuthorizationProvider.cs' = '0A31C3EFCBAE94086F6D90B7476A5AD2BA3D5C179CEE5736671CEB9D8B56BB48'
    'Backend/src/ToeicExam.EntityFrameworkCore/EntityFrameworkCore/Seed/Host/HostRoleAndUserCreator.cs' = '8BA62ED56012F89D0DF01E0022BCE02CB36C1021EC6885A718F45233FE1744CD'
    'Backend/src/ToeicExam.Web.Core/Controllers/TokenAuthController.cs' = '12BF73BCADDCD89AAFA0C719A2B73837BAFAF3ED59BAAE5349B98ACD507B0B26'
    'Backend/src/ToeicExam.Web.Mvc/Controllers/ToeicApiController.cs' = ''
    'Backend/src/ToeicExam.Web.Mvc/Properties/launchSettings.json' = '550973A7B855B40D1E8EDF153960AA95D06A6DC2687C80E3AA25DDA9FCCD6223'
    'Backend/src/ToeicExam.Web.Mvc/Startup/Startup.cs' = 'CB28A0B97F34E03A7FF745761FDB1A004829F4487B92B6C7E23A64379E043C73'
    'Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicModels.cs' = ''
    'Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicStore.cs' = ''
    'Backend/src/ToeicExam.Web.Mvc/Toeic/ToeicTimeoutWorker.cs' = ''
    'Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/index.html' = ''
    'Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/sample-exam.json' = ''
    'Backend/test/ToeicExam.Web.Tests/ToeicValidationTests.cs' = ''
    'Database/03_SmokeTest_Rollback.sql' = ''
    'Database/TOEIC_ALL_IN_ONE.sql' = ''
    'android/app/src/debug/AndroidManifest.xml' = 'B01A4541A8144C15BC617BAB7EB267C99FA1476368FBBDA5A12CDBF4E316A34C'
    'android/app/src/main/AndroidManifest.xml' = 'C84D9669BEEBBEF0AF2699DCB70FE128F7BB09B61746EF8557291B37F221CD58'
    'docs/HUONG_DAN_CHAY_TIEP.md' = ''
    'lib/main.dart' = 'B46576BB86CC7C1684CD21C3E7935BFBE29EF85095DF3ACCA6948B7A56600FF4'
    'lib/toeic/student_app.dart' = ''
    'lib/toeic/toeic_api.dart' = ''
    'test/toeic_api_test.dart' = ''
    'Backend/src/ToeicExam.Migrator/appsettings.json' = '9F3296FE5B9304542C020DE8FC0B8EB1D82C73B48F088B445B95ACBF9376568F'
    'Backend/src/ToeicExam.Web.Mvc/appsettings.json' = 'B6A1EB5772AE3187DED81534E3E2075847853303F04EF701B8743D1FA7783FFC'
}

# Refuse to overwrite edits made after the uploaded snapshot. Nothing has been written yet.
$conflicts = @()
foreach ($relative in $expected.Keys) {
    $path = Join-Path $root $relative
    $oldHash = $expected[$relative]
    if (Test-Path -LiteralPath $path) {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if (!$oldHash -or $actual -ne $oldHash) { $conflicts += $relative }
    } elseif ($oldHash) { $conflicts += $relative }
}
if ($conflicts.Count -gt 0) {
    throw ("Các file đã khác bản ZIP, chưa thay đổi file nào. Gửi danh sách này để ghép mã:`n" + ($conflicts -join "`n"))
}
# Only set the database name; never print or embed credentials from local configuration.
foreach ($relative in @('Backend/src/ToeicExam.Migrator/appsettings.json','Backend/src/ToeicExam.Web.Mvc/appsettings.json')) {
    $path = Join-Path $root $relative
    $config = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
    $connection = [string]$config.ConnectionStrings.Default
    if ($connection -notmatch '(?i)(Database|Initial Catalog)\s*=') { throw "Không tìm thấy Database trong $relative. Chưa ghi file." }
    $connection = [regex]::Replace($connection, '(?i)(Database|Initial Catalog)\s*=\s*[^;]*', ('Database=' + $DatabaseName))
    $config.ConnectionStrings.Default = $connection
    $files[$relative] = $config | ConvertTo-Json -Depth 100
}
Write-Host ("Sẽ cập nhật {0} file. Database: {1}. Server SQL giữ nguyên." -f $files.Count, $DatabaseName)
if ($CheckOnly) { Write-Host 'Kiểm tra xong. Chưa ghi file.'; exit 0 }
$backup = Join-Path $root ('TOEIC_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $backup | Out-Null
$manifest = @()
# Finish all backups before editing any source file.
foreach ($relative in $files.Keys) {
    $path = Join-Path $root $relative
    $existed = Test-Path -LiteralPath $path
    if ($existed) {
        $copy = Join-Path $backup ('original/' + $relative)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $copy) | Out-Null
        Copy-Item -LiteralPath $path -Destination $copy
    }
    $manifest += [pscustomobject]@{ path=$relative; existed=$existed; installedHash='' }
}
try {
    foreach ($item in $manifest) {
        $path = Join-Path $root $item.path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [System.IO.File]::WriteAllText($path, ([string]$files[$item.path]).TrimEnd([char[]]"`r`n") + "`n", $utf8)
        $item.installedHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    [System.IO.File]::WriteAllText((Join-Path $backup 'manifest.json'), (ConvertTo-Json -InputObject @($manifest) -Depth 5), $utf8)
    $restore = @'
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$items = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
foreach ($item in $items) {
    $file = Join-Path $project $item.path
    if (Test-Path -LiteralPath $file) {
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.installedHash) {
            throw ('File đã được sửa sau khi cập nhật; chưa khôi phục: ' + $item.path)
        }
    }
}
foreach ($item in $items) {
    $file = Join-Path $project $item.path
    if ($item.existed) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('original/' + $item.path)) -Destination $file -Force }
    elseif (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
Write-Host 'Đã khôi phục mã nguồn và cấu hình. Không thay đổi database.'
'@
    [System.IO.File]::WriteAllText((Join-Path $backup 'Restore.ps1'), $restore, (New-Object System.Text.UTF8Encoding($true)))
} catch {
    $failure = $_
    foreach ($item in $manifest) {
        $path = Join-Path $root $item.path
        if ($item.existed) { Copy-Item -LiteralPath (Join-Path $backup ('original/' + $item.path)) -Destination $path -Force }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    throw $failure
}
Write-Host 'Đã cập nhật mã nguồn. Chưa chạy build, migration hay SQL.' -ForegroundColor Green
Write-Host ('Bản sao lưu: ' + $backup)
Write-Host ('Hướng dẫn: ' + (Join-Path $root 'docs/HUONG_DAN_CHAY_TIEP.md'))
Write-Host 'Tiếp theo: kiểm tra schema toeic trong SSMS, dotnet build, chạy Migrator rồi chạy profile Toeic.Local.'
