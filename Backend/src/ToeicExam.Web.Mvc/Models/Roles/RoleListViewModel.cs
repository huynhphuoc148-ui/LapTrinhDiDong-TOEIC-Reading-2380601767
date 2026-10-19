using ToeicExam.Roles.Dto;
using System.Collections.Generic;

namespace ToeicExam.Web.Models.Roles;

public class RoleListViewModel
{
    public IReadOnlyList<PermissionDto> Permissions { get; set; }
}
