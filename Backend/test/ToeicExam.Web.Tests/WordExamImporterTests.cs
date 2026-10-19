using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security;
using System.Text;
using Abp.UI;
using ToeicExam.Web.Toeic;
using Xunit;

namespace ToeicExam.Web.Tests;

public class WordExamImporterTests
{
    [Fact]
    public void Imports_tagged_reading_docx_and_preserves_image_order()
    {
        using var file = CreateDocx(includeHeader: true, removeAnswerFor: null, includeImage: true);

        var exam = WordExamImporter.Import(file);

        Assert.Equal("Unit Reading Fixture", exam.Title);
        Assert.Equal(100, exam.Blocks.Sum(block => block.Questions.Count));
        Assert.Equal(30, exam.Blocks.Where(block => block.Part == 5).Sum(block => block.Questions.Count));
        Assert.Equal(16, exam.Blocks.Where(block => block.Part == 6).Sum(block => block.Questions.Count));
        Assert.Equal(54, exam.Blocks.Where(block => block.Part == 7).Sum(block => block.Questions.Count));
        var part6Passage = exam.Blocks.First(block => block.Part == 6).Passages.Single();
        Assert.Contains("{{131}}", part6Passage);
        Assert.Contains("[[TOEIC_IMAGE:data:image/png;base64,", part6Passage);
        Assert.True(part6Passage.IndexOf("{{134}}", StringComparison.Ordinal) <
                    part6Passage.IndexOf(WordExamImporter.ImageTokenPrefix, StringComparison.Ordinal));
    }

    [Fact]
    public void Rejects_image_only_docx_without_semantic_tags()
    {
        using var file = CreateDocx(includeHeader: false, removeAnswerFor: null, includeImage: true);

        var error = Assert.Throws<UserFriendlyException>(() => WordExamImporter.Import(file));

        Assert.Contains("[TOEIC_EXAM]", error.Message);
        Assert.Contains("không có dữ liệu nào được lưu", error.Message);
    }

    [Fact]
    public void Reports_invalid_question_number_when_answer_tag_is_missing()
    {
        using var file = CreateDocx(includeHeader: true, removeAnswerFor: 101, includeImage: false);

        var error = Assert.Throws<UserFriendlyException>(() => WordExamImporter.Import(file));

        Assert.Contains("101", error.Message);
    }

    private static MemoryStream CreateDocx(bool includeHeader, int? removeAnswerFor, bool includeImage)
    {
        var paragraphs = new List<string>();
        if (includeHeader)
        {
            paragraphs.Add("[TOEIC_EXAM]");
            paragraphs.Add("[TITLE] Unit Reading Fixture");
            paragraphs.Add("[DURATION_MINUTES] 75");
            AddPart5(paragraphs, removeAnswerFor);
            AddPart6(paragraphs, includeImage);
            AddPart7(paragraphs);
        }
        else
        {
            paragraphs.Add(null);
        }

        var xml = new StringBuilder();
        xml.Append("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:body>");
        foreach (var paragraph in paragraphs)
        {
            if (paragraph == null)
                xml.Append("<w:p><w:r><a:blip r:embed=\"rId1\"/></w:r></w:p>");
            else
                xml.Append("<w:p><w:r><w:t xml:space=\"preserve\">")
                    .Append(SecurityElement.Escape(paragraph))
                    .Append("</w:t></w:r></w:p>");
        }
        xml.Append("<w:sectPr/></w:body></w:document>");

        var file = new MemoryStream();
        using (var archive = new ZipArchive(file, ZipArchiveMode.Create, leaveOpen: true))
        {
            WriteEntry(archive, "word/document.xml", xml.ToString());
            if (includeImage)
            {
                WriteEntry(archive, "word/_rels/document.xml.rels",
                    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/pixel.png\"/></Relationships>");
                var image = archive.CreateEntry("word/media/pixel.png");
                using var stream = image.Open();
                stream.Write(Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nS8sAAAAASUVORK5CYII="));
            }
        }
        file.Position = 0;
        return file;
    }

    private static void AddPart5(List<string> paragraphs, int? removeAnswerFor)
    {
        paragraphs.Add("[PART 5]");
        paragraphs.Add("[SHUFFLE_QUESTIONS] true");
        for (var number = 101; number <= 130; number++)
            AddQuestion(paragraphs, number, removeAnswerFor);
        paragraphs.Add("[END_PART]");
    }

    private static void AddPart6(List<string> paragraphs, bool includeImage)
    {
        paragraphs.Add("[PART 6]");
        for (var first = 131; first <= 143; first += 4)
        {
            paragraphs.Add("[GROUP]");
            paragraphs.Add("[SHUFFLE_QUESTIONS] false");
            paragraphs.Add("[PASSAGE]");
            paragraphs.Add(string.Join(" ", Enumerable.Range(first, 4).Select(number => "{{" + number + "}}")));
            if (includeImage && first == 131) paragraphs.Add(null);
            paragraphs.Add("[END_PASSAGE]");
            for (var number = first; number < first + 4; number++)
                AddQuestion(paragraphs, number, null, allowEmptyStem: true);
            paragraphs.Add("[END_GROUP]");
        }
        paragraphs.Add("[END_PART]");
    }

    private static void AddPart7(List<string> paragraphs)
    {
        paragraphs.Add("[PART 7]");
        paragraphs.Add("[GROUP]");
        paragraphs.Add("[PASSAGE]");
        paragraphs.Add("This is a test-only passage.");
        paragraphs.Add("[END_PASSAGE]");
        for (var number = 147; number <= 200; number++) AddQuestion(paragraphs, number, null);
        paragraphs.Add("[END_GROUP]");
        paragraphs.Add("[END_PART]");
    }

    private static void AddQuestion(List<string> paragraphs, int number, int? removeAnswerFor, bool allowEmptyStem = false)
    {
        paragraphs.Add($"[QUESTION {number}]");
        paragraphs.Add("[SHUFFLE_OPTIONS] false");
        if (!allowEmptyStem)
        {
            paragraphs.Add("[STEM]");
            paragraphs.Add($"Test-only question {number}.");
        }
        paragraphs.Add("[CHOICE A]");
        paragraphs.Add("Choice A");
        paragraphs.Add("[CHOICE B]");
        paragraphs.Add("Choice B");
        paragraphs.Add("[CHOICE C]");
        paragraphs.Add("Choice C");
        paragraphs.Add("[CHOICE D]");
        paragraphs.Add("Choice D");
        if (removeAnswerFor != number) paragraphs.Add("[ANSWER] B");
        paragraphs.Add("[HINT]");
        paragraphs.Add("Test fixture hint.");
        paragraphs.Add("[EXPLANATION]");
        paragraphs.Add("Test fixture explanation.");
        paragraphs.Add("[END_QUESTION]");
    }

    private static void WriteEntry(ZipArchive archive, string path, string content)
    {
        var entry = archive.CreateEntry(path);
        using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
        writer.Write(content);
    }
}