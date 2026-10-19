using Abp.AspNetCore.Mvc.Views;
using Abp.Runtime.Session;
using Microsoft.AspNetCore.Mvc.Razor.Internal;

namespace ToeicExam.Web.Views;

public abstract class ToeicExamRazorPage<TModel> : AbpRazorPage<TModel>
{
    [RazorInject]
    public IAbpSession AbpSession { get; set; }

    protected ToeicExamRazorPage()
    {
        LocalizationSourceName = ToeicExamConsts.LocalizationSourceName;
    }
}
