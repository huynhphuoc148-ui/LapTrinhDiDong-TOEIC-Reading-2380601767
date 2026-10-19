using Abp.Events.Bus;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicExam.Configuration;
using ToeicExam.EntityFrameworkCore;
using ToeicExam.Migrator.DependencyInjection;
using Castle.MicroKernel.Registration;
using Microsoft.Extensions.Configuration;

namespace ToeicExam.Migrator;

[DependsOn(typeof(ToeicExamEntityFrameworkModule))]
public class ToeicExamMigratorModule : AbpModule
{
    private readonly IConfigurationRoot _appConfiguration;

    public ToeicExamMigratorModule(ToeicExamEntityFrameworkModule abpProjectNameEntityFrameworkModule)
    {
        abpProjectNameEntityFrameworkModule.SkipDbSeed = true;

        _appConfiguration = AppConfigurations.Get(
            typeof(ToeicExamMigratorModule).GetAssembly().GetDirectoryPathOrNull()
        );
    }

    public override void PreInitialize()
    {
        Configuration.DefaultNameOrConnectionString = _appConfiguration.GetConnectionString(
            ToeicExamConsts.ConnectionStringName
        );

        Configuration.BackgroundJobs.IsJobExecutionEnabled = false;
        Configuration.ReplaceService(
            typeof(IEventBus),
            () => IocManager.IocContainer.Register(
                Component.For<IEventBus>().Instance(NullEventBus.Instance)
            )
        );
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicExamMigratorModule).GetAssembly());
        ServiceCollectionRegistrar.Register(IocManager);
    }
}
