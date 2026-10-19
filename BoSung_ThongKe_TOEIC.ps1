# TOEIC: add exam-level statistics; preserve existing features.
param([string]$ProjectRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$base = Join-Path $ProjectRoot 'Backend\src\ToeicExam.Web.Mvc'
if (!(Test-Path $base)) { throw 'Dat file PS1 trong thu muc kiemtragk (cung cap Backend va lib).' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$edits = @()
$edits += @{ Path = 'Toeic\ToeicStore.cs'; Anchor = @'
    public async Task<object> Statistics(long person, long session)
'@
Insert = @'
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
'@
}
$edits += @{ Path = 'Controllers\ToeicApiController.cs'; Anchor = @'
    [HttpGet("teacher/sessions/{id:long}/statistics")]
'@
Insert = @'
    [HttpGet("teacher/exams/{id:long}/statistics")]
    public Task<IActionResult> ExamStatistics(long id) => Run(true, (db, p) => db.ExamStatistics(p, id));
'@
}
$edits += @{ Path = 'wwwroot\toeic\index.html'; Anchor = @'
          if (e.status === "Draft") {
'@
Insert = @'
          const statsButton = text("button", "Thống kê theo đề");
          statsButton.type = "button";
          statsButton.onclick = () => run(async () => {
            statsButton.disabled = true;
            try { await showExamStatistics(e.examId, e.title); }
            finally { statsButton.disabled = false; }
          });
          card.append(statsButton);
'@
}
$edits += @{ Path = 'wwwroot\toeic\index.html'; Anchor = @'
      async function load() {
'@
Insert = @'
      async function showExamStatistics(id, title) {
        const data = await api(`/api/toeic/teacher/exams/${id}/statistics`);
        let section = $("examStatisticsSection");
        if (!section) {
          section = document.createElement("section");
          section.id = "examStatisticsSection";
          $("reportSection").after(section);
        }
        section.replaceChildren();
        section.append(text("h2", "Thống kê theo đề: " + title));
        section.append(text("p", "Tổng hợp các ca do bạn quản lý, thuộc cùng đề. Chỉ tính bài đã nộp."));
        const s = data.summary;
        const number = value => value == null ? "—" : Number(value).toLocaleString("vi-VN", {maximumFractionDigits: 2});
        section.append(text("p", `Đã nộp: ${s.submittedAttempts} · Trung bình số câu đúng: ${number(s.averageCorrect)} · Tỷ lệ đúng trung bình: ${number(s.averagePercent)}%`));
        const wrap = document.createElement("div");
        wrap.style.overflowX = "auto";
        const table = document.createElement("table");
        const head = document.createElement("thead"), row = document.createElement("tr");
        ["Sinh viên", "Ca thi", "Phiên bản", "Đúng", "Sai", "Bỏ trống", "Nộp lúc"].forEach(x => row.append(text("th", x)));
        head.append(row); table.append(head);
        const body = document.createElement("tbody");
        for (const a of data.attempts) {
          const row = document.createElement("tr");
          [a.fullName, a.sessionName, a.versionNo, a.correctCount, a.wrongCount, a.skippedCount, date(a.submittedAt)].forEach(x => row.append(text("td", x)));
          body.append(row);
        }
        table.append(body); wrap.append(table); section.append(wrap);
        if (!data.attempts.length) section.append(text("p", "Chưa có bài đã nộp."));
        section.append(text("h3", "Top 10 câu chọn sai"));
        section.append(text("p", "Bỏ trống được đếm riêng. Câu thuộc phiên bản khác nhau được thống kê riêng.", "hint"));
        for (const q of data.topWrong) section.append(text("p", `Phiên bản ${q.versionNo} · Câu ${q.originalNumber}: ${q.wrongCount} chọn sai / ${q.seenCount} bài; ${q.skippedCount} bỏ trống`));
        if (!data.topWrong.length) section.append(text("p", "Chưa có câu được chọn sai."));
        section.scrollIntoView({behavior: "smooth", block: "start"});
      }
'@
}
$pending = @{}
foreach ($edit in $edits) {
    $path = Join-Path $base $edit.Path
    if (!(Test-Path $path)) { throw "Khong tim thay $path" }
    if (!$pending.ContainsKey($path)) { $pending[$path] = [IO.File]::ReadAllText($path) }
    $content = $pending[$path].Replace("`r`n", "`n")
    $insert = $edit.Insert.Replace("`r`n", "`n")
    $anchor = $edit.Anchor.Replace("`r`n", "`n")
    if ($content.Contains($insert)) { continue }
    if ([regex]::Matches($content, [regex]::Escape($anchor)).Count -ne 1) {
        throw "Code khac ban da kiem tra: $path. Chua sua file nao; gui file nay de doi chieu."
    }
    $pending[$path] = $content.Replace($anchor, $insert + "`n" + $anchor)
}
$backup = Join-Path $ProjectRoot ('backup-thongke-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
foreach ($path in $pending.Keys) {
    $relative = $path.Substring($base.Length).TrimStart([char]'\', [char]'/')
    $copy = Join-Path $backup $relative
    New-Item -ItemType Directory -Path (Split-Path $copy) -Force | Out-Null
    Copy-Item -LiteralPath $path -Destination $copy
}
foreach ($path in $pending.Keys) { [IO.File]::WriteAllText($path, $pending[$path], $utf8) }
Write-Host 'Da them thong ke theo de. Khong thay doi SQL hay du lieu.' -ForegroundColor Green
Write-Host "Ban sao luu: $backup"
Write-Host 'Tiep theo: dotnet build, chay lai backend, Ctrl+F5 tren trang giang vien.'
