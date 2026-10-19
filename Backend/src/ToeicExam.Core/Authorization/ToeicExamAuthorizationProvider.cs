using Abp.Authorization;
using Abp.Localization;
using Abp.MultiTenancy;

namespace ToeicExam.Authorization;

public class ToeicExamAuthorizationProvider : AuthorizationProvider
{
    public override void SetPermissions(IPermissionDefinitionContext context)
    {
        context.CreatePermission("Pages.Toeic.Manage", new FixedLocalizableString("Quản lý đề và ca thi TOEIC"), multiTenancySides: MultiTenancySides.Host);
        context.CreatePermission(PermissionNames.Pages_Users, L("Users"));
        context.CreatePermission(PermissionNames.Pages_Users_Activation, L("UsersActivation"));
        context.CreatePermission(PermissionNames.Pages_Roles, L("Roles"));
        context.CreatePermission(PermissionNames.Pages_Tenants, L("Tenants"), multiTenancySides: MultiTenancySides.Host);
    }

    private static ILocalizableString L(string name)
    {
        return new LocalizableString(name, ToeicExamConsts.LocalizationSourceName);
    }
}
