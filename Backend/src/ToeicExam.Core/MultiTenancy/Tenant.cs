using Abp.MultiTenancy;
using ToeicExam.Authorization.Users;

namespace ToeicExam.MultiTenancy;

public class Tenant : AbpTenant<User>
{
    public Tenant()
    {
    }

    public Tenant(string tenancyName, string name)
        : base(tenancyName, name)
    {
    }
}
