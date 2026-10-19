using ToeicExam.Roles.Dto;
using System.Collections.Generic;

namespace ToeicExam.Web.Models.Users;

public class UserListViewModel
{
    public IReadOnlyList<RoleDto> Roles { get; set; }
}
