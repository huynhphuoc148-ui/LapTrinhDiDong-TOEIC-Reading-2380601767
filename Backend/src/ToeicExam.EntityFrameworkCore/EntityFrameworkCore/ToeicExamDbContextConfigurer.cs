using Microsoft.EntityFrameworkCore;
using System.Data.Common;

namespace ToeicExam.EntityFrameworkCore;

public static class ToeicExamDbContextConfigurer
{
    public static void Configure(DbContextOptionsBuilder<ToeicExamDbContext> builder, string connectionString)
    {
        builder.UseSqlServer(connectionString);
    }

    public static void Configure(DbContextOptionsBuilder<ToeicExamDbContext> builder, DbConnection connection)
    {
        builder.UseSqlServer(connection);
    }
}
