using Abp.Zero.EntityFrameworkCore;
using ToeicExam.Authorization.Roles;
using ToeicExam.Authorization.Users;
using ToeicExam.MultiTenancy;
using Microsoft.EntityFrameworkCore;

namespace ToeicExam.EntityFrameworkCore;

public class ToeicExamDbContext : AbpZeroDbContext<Tenant, Role, User, ToeicExamDbContext>
{
    /* Define a DbSet for each entity of the application */

    public ToeicExamDbContext(DbContextOptions<ToeicExamDbContext> options)
        : base(options)
    {
    }
}
