using Abp.Application.Services;
using ToeicExam.MultiTenancy.Dto;

namespace ToeicExam.MultiTenancy;

public interface ITenantAppService : IAsyncCrudAppService<TenantDto, int, PagedTenantResultRequestDto, CreateTenantDto, TenantDto>
{
}

