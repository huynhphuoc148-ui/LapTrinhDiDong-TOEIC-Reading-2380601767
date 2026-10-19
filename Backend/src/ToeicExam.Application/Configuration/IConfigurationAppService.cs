using ToeicExam.Configuration.Dto;
using System.Threading.Tasks;

namespace ToeicExam.Configuration;

public interface IConfigurationAppService
{
    Task ChangeUiTheme(ChangeUiThemeInput input);
}
