using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicExam.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace ToeicExam.Web.Startup;

[DependsOn(typeof(ToeicExamWebCoreModule))]
public class ToeicExamWebMvcModule : AbpModule
{
    private readonly IWebHostEnvironment _env;
    private readonly IConfigurationRoot _appConfiguration;

    public ToeicExamWebMvcModule(IWebHostEnvironment env)
    {
        _env = env;
        _appConfiguration = env.GetAppConfiguration();
    }

    public override void PreInitialize()
    {
        Configuration.Navigation.Providers.Add<ToeicExamNavigationProvider>();
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicExamWebMvcModule).GetAssembly());
    }
}
