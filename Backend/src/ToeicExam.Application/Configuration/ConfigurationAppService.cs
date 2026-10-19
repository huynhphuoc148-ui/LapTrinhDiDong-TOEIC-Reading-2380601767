using Abp.Authorization;
using Abp.Runtime.Session;
using ToeicExam.Configuration.Dto;
using System.Threading.Tasks;

namespace ToeicExam.Configuration;

[AbpAuthorize]
public class ConfigurationAppService : ToeicExamAppServiceBase, IConfigurationAppService
{
    public async Task ChangeUiTheme(ChangeUiThemeInput input)
    {
        await SettingManager.ChangeSettingForUserAsync(AbpSession.ToUserIdentifier(), AppSettingNames.UiTheme, input.Theme);
    }
}
