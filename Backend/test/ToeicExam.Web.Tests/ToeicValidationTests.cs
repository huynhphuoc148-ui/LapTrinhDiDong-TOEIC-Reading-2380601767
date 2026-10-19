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
    [Fact] public void Reports_multiple_errors_with_question_context()
    {
        var exam=Valid();var question=exam.Blocks[0].Questions[0];question.Stem="";question.Hint="";question.Answer="E";
        var errors=ToeicStore.GetExamValidationErrors(exam);
        Assert.Contains(errors,error=>error.Contains("câu 101"));
        Assert.True(errors.Count(error=>error.Contains("câu 101"))>=3);
    }
}
