using ToeicExam.Debugging;

namespace ToeicExam;

public class ToeicExamConsts
{
    public const string LocalizationSourceName = "ToeicExam";

    public const string ConnectionStringName = "Default";

    public const bool MultiTenancyEnabled = true;


    /// <summary>
    /// Default pass phrase for SimpleStringCipher decrypt/encrypt operations
    /// </summary>
    public static readonly string DefaultPassPhrase =
        DebugHelper.IsDebug ? "gsKxGZ012HLL3MI5" : "1de8210f2ef242438bdc77c3e439e3e3";
}
