using ToeicExam.Roles.Dto;
using System.Collections.Generic;

namespace ToeicExam.Web.Models.Common;

public interface IPermissionsEditViewModel
{
    List<FlatPermissionDto> Permissions { get; set; }
}