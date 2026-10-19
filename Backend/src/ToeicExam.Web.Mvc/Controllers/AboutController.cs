using Abp.AspNetCore.Mvc.Authorization;
using ToeicExam.Controllers;
using Microsoft.AspNetCore.Mvc;

namespace ToeicExam.Web.Controllers;

[AbpMvcAuthorize]
public class AboutController : ToeicExamControllerBase
{
    public ActionResult Index()
    {
        return View();
    }
}
