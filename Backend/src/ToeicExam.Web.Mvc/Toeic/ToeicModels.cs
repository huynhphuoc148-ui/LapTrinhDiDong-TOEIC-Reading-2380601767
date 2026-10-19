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
