using System.ComponentModel.DataAnnotations;

namespace ToeicExam.Users.Dto;

public class ChangeUserLanguageDto
{
    [Required]
    public string LanguageName { get; set; }
}