using Abp.AspNetCore.Mvc.ViewComponents;

namespace ToeicExam.Web.Views;

public abstract class ToeicExamViewComponent : AbpViewComponent
{
    protected ToeicExamViewComponent()
    {
        LocalizationSourceName = ToeicExamConsts.LocalizationSourceName;
    }
}
