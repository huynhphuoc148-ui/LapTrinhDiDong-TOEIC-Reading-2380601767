using Abp.AspNetCore;
using Abp.AspNetCore.TestBase;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicExam.EntityFrameworkCore;
using ToeicExam.Web.Startup;
using Microsoft.AspNetCore.Mvc.ApplicationParts;

namespace ToeicExam.Web.Tests;

[DependsOn(
    typeof(ToeicExamWebMvcModule),
    typeof(AbpAspNetCoreTestBaseModule)
)]
public class ToeicExamWebTestModule : AbpModule
{
    public ToeicExamWebTestModule(ToeicExamEntityFrameworkModule abpProjectNameEntityFrameworkModule)
    {
        abpProjectNameEntityFrameworkModule.SkipDbContextRegistration = true;
    }

    public override void PreInitialize()
    {
        Configuration.UnitOfWork.IsTransactional = false; //EF Core InMemory DB does not support transactions.
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicExamWebTestModule).GetAssembly());
    }

    public override void PostInitialize()
    {
        IocManager.Resolve<ApplicationPartManager>()
            .AddApplicationPartsIfNotAddedBefore(typeof(ToeicExamWebMvcModule).Assembly);
    }
}