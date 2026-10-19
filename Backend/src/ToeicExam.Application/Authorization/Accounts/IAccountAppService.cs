using Abp.Application.Services;
using ToeicExam.Authorization.Accounts.Dto;
using System.Threading.Tasks;

namespace ToeicExam.Authorization.Accounts;

public interface IAccountAppService : IApplicationService
{
    Task<IsTenantAvailableOutput> IsTenantAvailable(IsTenantAvailableInput input);

    Task<RegisterOutput> Register(RegisterInput input);
}
