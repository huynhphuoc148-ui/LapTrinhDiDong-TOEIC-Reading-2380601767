using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using Abp.UI;

namespace ToeicExam.Web.Toeic;

public static class WordExamImporter
{
    public const string ImageTokenPrefix = "[[TOEIC_IMAGE:";
    public const int MaxDocumentBytes = 40_000_000;

    private const long MaxExpandedBytes = 100_000_000;
    private const int MaxImageBytes = 2_000_000;
    private const int MaxTotalImageBytes = 8_000_000;
    private static readonly XNamespace Word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    private static readonly XNamespace Drawing = "http://schemas.openxmlformats.org/drawingml/2006/main";
    private static readonly XNamespace Relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private static readonly Regex TagPattern = new(@"^\s*\[(?<tag>[^\]]+)\]\s*(?<value>.*)$", RegexOptions.Compiled);

    public static ExamInput Import(Stream source)
    {
        if (source == null || !source.CanRead)
            throw new UserFriendlyException("Không đọc được file Word.");
        if (source.CanSeek && source.Length > MaxDocumentBytes)
            throw new UserFriendlyException("File DOCX vượt quá giới hạn 40 MB.");

        try
        {
            using var archive = new ZipArchive(source, ZipArchiveMode.Read, leaveOpen: true);
            if (archive.Entries.Sum(entry => entry.Length) > MaxExpandedBytes)
                throw new UserFriendlyException("Nội dung DOCX giải nén vượt quá giới hạn an toàn.");

            var documentEntry = archive.GetEntry("word/document.xml");
            if (documentEntry == null)
                throw new UserFriendlyException("File không phải tài liệu DOCX hợp lệ (thiếu word/document.xml).");

            var document = ReadXml(documentEntry);
            var body = document.Root?.Element(Word + "body");
            var paragraphs = body?.Descendants(Word + "p").Select(ReadParagraph).ToList()
                ?? new List<WordParagraph>();
            var hasHeaderTag = paragraphs.Any(paragraph =>
            {
                var match = TagPattern.Match(paragraph.PlainText);
                return match.Success && NormalizeTag(match.Groups["tag"].Value) == "TOEIC_EXAM";
            });
            if (!hasHeaderTag)
                throw new UserFriendlyException("Thiếu thẻ [TOEIC_EXAM]. File này chưa theo quy ước nhập đề Word; không có dữ liệu nào được lưu.");

            var relationships = ReadRelationships(archive);
            var parser = new Parser(archive, relationships);
            var exam = parser.Parse(paragraphs);
            if (parser.Errors.Count > 0)
                throw new UserFriendlyException(FormatErrors(parser.Errors));

            try
            {
                ToeicStore.ValidateExam(exam);
            }
            catch (UserFriendlyException exception)
            {
                throw new UserFriendlyException("Đề chưa hợp lệ:\n" + exception.Message);
            }

            return exam;
        }
        catch (UserFriendlyException)
        {
            throw;
        }
        catch (InvalidDataException)
        {
            throw new UserFriendlyException("File không phải DOCX hợp lệ hoặc cấu trúc ZIP bị hỏng.");
        }
        catch (XmlException)
        {
            throw new UserFriendlyException("DOCX có XML không hợp lệ. Hãy lưu lại file bằng Word rồi thử lại.");
        }
        catch (IOException)
        {
            throw new UserFriendlyException("Không đọc được nội dung file DOCX.");
        }
    }

    private static XDocument ReadXml(ZipArchiveEntry entry)
    {
        using var stream = entry.Open();
        using var reader = XmlReader.Create(stream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = 50_000_000
        });
        return XDocument.Load(reader, LoadOptions.None);
    }

    private static Dictionary<string, string> ReadRelationships(ZipArchive archive)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var entry = archive.GetEntry("word/_rels/document.xml.rels");
        if (entry == null) return result;

        var document = ReadXml(entry);
        foreach (var relationship in document.Root?.Elements().Where(element =>
                     (string)element.Attribute("Type") == "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image")
                 ?? Enumerable.Empty<XElement>())
        {
            var id = (string)relationship.Attribute("Id");
            var target = (string)relationship.Attribute("Target");
            var targetMode = (string)relationship.Attribute("TargetMode");
            if (!string.IsNullOrWhiteSpace(id) && !string.IsNullOrWhiteSpace(target) &&
                !string.Equals(targetMode, "External", StringComparison.OrdinalIgnoreCase))
                result[id] = target;
        }
        return result;
    }

    private static WordParagraph ReadParagraph(XElement paragraph)
    {
        var tokens = new List<WordToken>();
        foreach (var node in paragraph.DescendantsAndSelf())
        {
            if (node.Name == Word + "t") tokens.Add(new WordToken(node.Value, null));
            else if (node.Name == Word + "tab") tokens.Add(new WordToken("\t", null));
            else if (node.Name == Word + "br") tokens.Add(new WordToken("\n", null));
            else if (node.Name == Drawing + "blip")
                tokens.Add(new WordToken(null,
                    (string)node.Attribute(Relationships + "embed") ??
                    (string)node.Attribute(Relationships + "link") ?? string.Empty));
        }
        return new WordParagraph(tokens);
    }

    private static string NormalizeTag(string value) =>
        Regex.Replace(value.Trim().ToUpperInvariant(), @"\s+", " ");

    private static string FormatErrors(IEnumerable<string> errors) =>
        "File Word không được lưu vì có lỗi:\n" + string.Join("\n", errors.Distinct());

    private sealed record WordToken(string Text, string RelationshipId);

    private sealed class WordParagraph
    {
        public WordParagraph(List<WordToken> tokens) => Tokens = tokens;
        public List<WordToken> Tokens { get; }
        public string PlainText => string.Concat(Tokens.Where(token => token.Text != null).Select(token => token.Text));
    }

    private sealed class Parser
    {
        private readonly ZipArchive _archive;
        private readonly IReadOnlyDictionary<string, string> _relationships;
        private readonly Dictionary<string, string> _imageTokens = new(StringComparer.Ordinal);
        private readonly StringBuilder _fieldContent = new();
        private readonly List<string> _errors = new();
        private ExamInput _exam = new();
        private BlockInput _group;
        private BlockInput _partFiveBlock;
        private QuestionInput _question;
        private int _part;
        private int _partFiveShuffle;
        private int _totalImageBytes;
        private string _field;
        private string _fieldLocation;
        private int _paragraphNumber;

        public Parser(ZipArchive archive, IReadOnlyDictionary<string, string> relationships)
        {
            _archive = archive;
            _relationships = relationships;
        }

        public IReadOnlyList<string> Errors => _errors;

        public ExamInput Parse(IEnumerable<WordParagraph> paragraphs)
        {
            foreach (var paragraph in paragraphs)
            {
                _paragraphNumber++;
                ParseParagraph(paragraph);
            }

            FlushField();
            if (_question != null) AddError($"Câu {_question.Number}: thiếu [END_QUESTION].");
            if (_group != null) AddError($"Part {_part}: thiếu [END_GROUP].");
            if (_part != 0) AddError($"Part {_part}: thiếu [END_PART].");
            if (string.IsNullOrWhiteSpace(_exam.Title)) AddError("Thiếu [TITLE] tên đề.");
            if (_exam.Blocks.Count == 0) AddError("Không có nhóm câu hỏi nào trong tài liệu.");
            return _exam;
        }

        private void ParseParagraph(WordParagraph paragraph)
        {
            var match = TagPattern.Match(paragraph.PlainText);
            if (!match.Success)
            {
                if (_field == null)
                {
                    if (paragraph.PlainText.Trim().Length > 0 || paragraph.Tokens.Any(token => token.RelationshipId != null))
                        AddError($"Đoạn Word {_paragraphNumber}: nội dung nằm ngoài thẻ trường.");
                    return;
                }
                AppendParagraph(paragraph.Tokens);
                return;
            }

            var tag = NormalizeTag(match.Groups["tag"].Value);
            var value = match.Groups["value"].Value.Trim();
            if (_field != null && tag is not "END_PASSAGE" and not "END_QUESTION" and not "END_GROUP" and not "END_PART")
                FlushField();

            if (tag.StartsWith("QUESTION ", StringComparison.Ordinal))
            {
                StartQuestion(tag["QUESTION ".Length..]);
                return;
            }

            switch (tag)
            {
                case "TOEIC_EXAM":
                    if (value.Length > 0) AddError("Đoạn Word " + _paragraphNumber + ": [TOEIC_EXAM] không nhận nội dung cùng dòng.");
                    break;
                case "TITLE":
                    if (_exam.Title != null) AddError("Đoạn Word " + _paragraphNumber + ": thẻ [TITLE] bị lặp.");
                    else _exam.Title = value;
                    break;
                case "DURATION_MINUTES":
                    if (!int.TryParse(value, out var duration) || duration != 75)
                        AddError("Đoạn Word " + _paragraphNumber + ": [DURATION_MINUTES] phải bằng 75.");
                    break;
                case "PART 5":
                case "PART 6":
                case "PART 7":
                    StartPart(int.Parse(tag[^1].ToString()));
                    break;
                case "END_PART":
                    EndPart();
                    break;
                case "GROUP":
                    StartGroup();
                    break;
                case "END_GROUP":
                    EndGroup();
                    break;
                case "SHUFFLE_QUESTIONS":
                    if (TryBool(value, "SHUFFLE_QUESTIONS", out var shuffle))
                    {
                        if (_group != null) _group.Shuffle = shuffle;
                        else if (_part == 5) _partFiveShuffle = shuffle ? 1 : 0;
                        else AddError($"Đoạn Word {_paragraphNumber}: [SHUFFLE_QUESTIONS] cần nằm trong [GROUP].");
                    }
                    break;
                case "QUESTION":
                    StartQuestion(value);
                    break;
                case "END_QUESTION":
                    EndQuestion();
                    break;
                case "SHUFFLE_OPTIONS":
                    if (RequireQuestion("SHUFFLE_OPTIONS") && TryBool(value, "SHUFFLE_OPTIONS", out var shuffleOptions))
                        _question.ShuffleOptions = shuffleOptions;
                    break;
                case "PASSAGE":
                    if (_group == null) AddError($"Đoạn Word {_paragraphNumber}: [PASSAGE] phải nằm trong [GROUP].");
                    else StartField("passage", $"Part {_part}, nhóm {_exam.Blocks.IndexOf(_group) + 1}", paragraph, match);
                    break;
                case "END_PASSAGE":
                    if (_field != "passage") AddError($"Đoạn Word {_paragraphNumber}: [END_PASSAGE] không có [PASSAGE] tương ứng.");
                    else FlushField();
                    break;
                case "STEM":
                    if (RequireQuestion("STEM")) StartField("stem", $"Câu {_question.Number}", paragraph, match);
                    break;
                case "CHOICE A":
                case "CHOICE B":
                case "CHOICE C":
                case "CHOICE D":
                    if (RequireQuestion(tag)) StartField("choice" + tag[^1], $"Câu {_question.Number}, lựa chọn {tag[^1]}", paragraph, match);
                    break;
                case "ANSWER":
                    if (RequireQuestion("ANSWER")) _question.Answer = value.ToUpperInvariant();
                    break;
                case "HINT":
                    if (RequireQuestion("HINT")) StartField("hint", $"Câu {_question.Number}", paragraph, match);
                    break;
                case "EXPLANATION":
                    if (RequireQuestion("EXPLANATION")) StartField("explanation", $"Câu {_question.Number}", paragraph, match);
                    break;
                default:
                    AddError($"Đoạn Word {_paragraphNumber}: thẻ [{tag}] không được hỗ trợ.");
                    break;
            }
        }

        private void StartPart(int part)
        {
            if (_part != 0 || _group != null || _question != null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: phải kết thúc Part trước khi mở Part {part}.");
                return;
            }
            _part = part;
            _partFiveBlock = null;
            _partFiveShuffle = 0;
        }

        private void EndPart()
        {
            if (_part == 0 || _group != null || _question != null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: [END_PART] không đúng vị trí.");
                return;
            }
            _part = 0;
        }

        private void StartGroup()
        {
            if (_part is not 6 and not 7 || _group != null || _question != null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: [GROUP] chỉ dùng cho Part 6/7 và không được lồng nhau.");
                return;
            }
            _group = new BlockInput { Part = _part };
            _exam.Blocks.Add(_group);
        }

        private void EndGroup()
        {
            if (_group == null || _question != null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: [END_GROUP] không đúng vị trí.");
                return;
            }
            if (_group.Questions.Count == 0) AddError($"Part {_part}, nhóm {_exam.Blocks.IndexOf(_group) + 1}: không có câu hỏi.");
            if (_group.Passages.Count == 0) AddError($"Part {_part}, nhóm {_exam.Blocks.IndexOf(_group) + 1}: thiếu [PASSAGE].");
            _group = null;
        }

        private void StartQuestion(string value)
        {
            if (_part == 0 || _question != null || !int.TryParse(value, out var number))
            {
                AddError($"Đoạn Word {_paragraphNumber}: [QUESTION] cần số câu và phải nằm trong Part.");
                return;
            }
            if (_part == 5)
            {
                if (_group != null) AddError($"Câu {number}: Part 5 không dùng [GROUP].");
                _partFiveBlock = new BlockInput { Part = 5, Shuffle = _partFiveShuffle == 1 };
                _exam.Blocks.Add(_partFiveBlock);
            }
            else if (_group == null)
            {
                AddError($"Câu {number}: Part {_part} phải nằm trong [GROUP].");
                return;
            }
            _question = new QuestionInput { Number = number };
        }

        private void EndQuestion()
        {
            if (_question == null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: [END_QUESTION] không có câu hỏi đang mở.");
                return;
            }
            FlushField();
            var block = _part == 5 ? _partFiveBlock : _group;
            if (block != null) block.Questions.Add(_question);
            _question = null;
        }

        private void StartField(string field, string location, WordParagraph paragraph, Match tagMatch)
        {
            _field = field;
            _fieldLocation = location;
            _fieldContent.Clear();
            var remainder = tagMatch.Groups["value"].Value;
            if (!string.IsNullOrWhiteSpace(remainder)) _fieldContent.Append(remainder.Trim());
            foreach (var token in paragraph.Tokens.Where(token => token.RelationshipId != null))
            {
                if (_fieldContent.Length > 0) _fieldContent.Append('\n');
                _fieldContent.Append(ImageToken(token.RelationshipId));
            }
        }

        private void AppendParagraph(IEnumerable<WordToken> tokens)
        {
            if (_fieldContent.Length > 0) _fieldContent.Append('\n');
            foreach (var token in tokens)
            {
                if (token.Text != null) _fieldContent.Append(token.Text);
                else if (token.RelationshipId != null) _fieldContent.Append(ImageToken(token.RelationshipId));
            }
        }

        private void FlushField()
        {
            if (_field == null) return;
            var value = _fieldContent.ToString().Trim();
            switch (_field)
            {
                case "passage":
                    if (_group != null && value.Length > 0) _group.Passages.Add(value);
                    else AddError($"{_fieldLocation}: nội dung [PASSAGE] rỗng.");
                    break;
                case "stem":
                    if (_question != null) _question.Stem = value;
                    break;
                case "choiceA":
                case "choiceB":
                case "choiceC":
                case "choiceD":
                    if (_question != null) _question.Choices[_field[^1].ToString()] = value;
                    break;
                case "hint":
                    if (_question != null) _question.Hint = value;
                    break;
                case "explanation":
                    if (_question != null) _question.Explanation = value;
                    break;
            }
            _field = null;
            _fieldLocation = null;
            _fieldContent.Clear();
        }

        private string ImageToken(string relationshipId)
        {
            if (string.IsNullOrWhiteSpace(relationshipId) || !_relationships.TryGetValue(relationshipId, out var target))
            {
                AddError($"Đoạn Word {_paragraphNumber}: ảnh tham chiếu không có trong document relationships.");
                return string.Empty;
            }
            if (_imageTokens.TryGetValue(relationshipId, out var cached)) return cached;

            var normalizedTarget = Uri.UnescapeDataString(target).Replace('\\', '/');
            if (normalizedTarget.StartsWith('/') || normalizedTarget.Split('/').Any(segment => segment == "..") ||
                !normalizedTarget.StartsWith("media/", StringComparison.OrdinalIgnoreCase))
            {
                AddError($"Đoạn Word {_paragraphNumber}: đường dẫn ảnh không an toàn.");
                return string.Empty;
            }
            var entry = _archive.GetEntry("word/" + normalizedTarget);
            if (entry == null || entry.Length == 0 || entry.Length > MaxImageBytes)
            {
                AddError($"Đoạn Word {_paragraphNumber}: ảnh thiếu, rỗng hoặc lớn hơn 2 MB.");
                return string.Empty;
            }
            _totalImageBytes += (int)entry.Length;
            if (_totalImageBytes > MaxTotalImageBytes)
            {
                AddError("Tổng dung lượng ảnh trong đề vượt quá 8 MB.");
                return string.Empty;
            }

            var extension = Path.GetExtension(normalizedTarget).ToLowerInvariant();
            var mime = extension switch
            {
                ".png" => "image/png",
                ".jpg" or ".jpeg" => "image/jpeg",
                ".gif" => "image/gif",
                ".webp" => "image/webp",
                _ => null
            };
            if (mime == null)
            {
                AddError($"Đoạn Word {_paragraphNumber}: ảnh {extension} không được hỗ trợ; dùng PNG, JPEG, GIF hoặc WebP.");
                return string.Empty;
            }

            using var imageStream = entry.Open();
            using var buffer = new MemoryStream((int)entry.Length);
            imageStream.CopyTo(buffer);
            var imageBytes = buffer.ToArray();
            if (!HasImageSignature(imageBytes, mime))
            {
                AddError($"Đoạn Word {_paragraphNumber}: nội dung ảnh không khớp định dạng {mime}.");
                return string.Empty;
            }
            var token = $"{ImageTokenPrefix}data:{mime};base64,{Convert.ToBase64String(imageBytes)}]]";
            _imageTokens[relationshipId] = token;
            return token;
        }

        private static bool HasImageSignature(byte[] bytes, string mime) => mime switch
        {
            "image/png" => bytes.Length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A,
            "image/jpeg" => bytes.Length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF,
            "image/gif" => bytes.Length >= 6 && Encoding.ASCII.GetString(bytes, 0, 3) == "GIF",
            "image/webp" => bytes.Length >= 12 && Encoding.ASCII.GetString(bytes, 0, 4) == "RIFF" && Encoding.ASCII.GetString(bytes, 8, 4) == "WEBP",
            _ => false
        };

        private bool RequireQuestion(string field)
        {
            if (_question != null) return true;
            AddError($"Đoạn Word {_paragraphNumber}: [{field}] nằm ngoài [QUESTION].");
            return false;
        }

        private bool TryBool(string value, string field, out bool result)
        {
            if (bool.TryParse(value, out result)) return true;
            AddError($"Đoạn Word {_paragraphNumber}: [{field}] chỉ nhận true hoặc false.");
            return false;
        }

        private void AddError(string error) => _errors.Add(error);
    }
}