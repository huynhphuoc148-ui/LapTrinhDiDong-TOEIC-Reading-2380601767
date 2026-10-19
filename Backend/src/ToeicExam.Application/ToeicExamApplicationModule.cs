using Abp.AutoMapper;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicExam.Authorization;

namespace ToeicExam;

[DependsOn(
    typeof(ToeicExamCoreModule),
    typeof(AbpAutoMapperModule))]
public class ToeicExamApplicationModule : AbpModule
{
    public override void PreInitialize()
    {
        Configuration.Authorization.Providers.Add<ToeicExamAuthorizationProvider>();
    }

    public override void Initialize()
    {
        var thisAssembly = typeof(ToeicExamApplicationModule).GetAssembly();

        IocManager.RegisterAssemblyByConvention(thisAssembly);

        Configuration.Modules.AbpAutoMapper().Configurators.Add(
            // Scan the assembly for classes which inherit from AutoMapper.Profile
            cfg => cfg.AddMaps(thisAssembly)
        );
    }
}
