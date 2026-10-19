using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicExam.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace ToeicExam.Web.Host.Startup
{
    [DependsOn(
       typeof(ToeicExamWebCoreModule))]
    public class ToeicExamWebHostModule : AbpModule
    {
        private readonly IWebHostEnvironment _env;
        private readonly IConfigurationRoot _appConfiguration;

        public ToeicExamWebHostModule(IWebHostEnvironment env)
        {
            _env = env;
            _appConfiguration = env.GetAppConfiguration();
        }

        public override void Initialize()
        {
            IocManager.RegisterAssemblyByConvention(typeof(ToeicExamWebHostModule).GetAssembly());
        }
    }
}
