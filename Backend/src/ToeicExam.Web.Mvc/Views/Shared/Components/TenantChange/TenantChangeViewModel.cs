using Abp.AutoMapper;
using ToeicExam.Sessions.Dto;

namespace ToeicExam.Web.Views.Shared.Components.TenantChange;

[AutoMapFrom(typeof(GetCurrentLoginInformationsOutput))]
public class TenantChangeViewModel
{
    public TenantLoginInfoDto Tenant { get; set; }
}
