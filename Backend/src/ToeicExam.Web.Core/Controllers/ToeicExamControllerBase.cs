using Abp.AspNetCore.Mvc.Controllers;
using Abp.IdentityFramework;
using Microsoft.AspNetCore.Identity;

namespace ToeicExam.Controllers
{
    public abstract class ToeicExamControllerBase : AbpController
    {
        protected ToeicExamControllerBase()
        {
            LocalizationSourceName = ToeicExamConsts.LocalizationSourceName;
        }

        protected void CheckErrors(IdentityResult identityResult)
        {
            identityResult.CheckErrors(LocalizationManager);
        }
    }
}
