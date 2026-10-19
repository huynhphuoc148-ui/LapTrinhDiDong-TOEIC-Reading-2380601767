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
