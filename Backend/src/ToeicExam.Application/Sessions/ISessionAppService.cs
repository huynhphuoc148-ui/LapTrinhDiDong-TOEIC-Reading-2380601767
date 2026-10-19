using Abp.Application.Services;
using ToeicExam.Sessions.Dto;
using System.Threading.Tasks;

namespace ToeicExam.Sessions;

public interface ISessionAppService : IApplicationService
{
    Task<GetCurrentLoginInformationsOutput> GetCurrentLoginInformations();
}
