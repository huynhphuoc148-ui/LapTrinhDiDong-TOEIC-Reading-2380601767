using Abp.Authorization;
using ToeicExam.Authorization.Roles;
using ToeicExam.Authorization.Users;

namespace ToeicExam.Authorization;

public class PermissionChecker : PermissionChecker<Role, User>
{
    public PermissionChecker(UserManager userManager)
        : base(userManager)
    {
    }
}
