using FlaUI.UIA3;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Work done once per test run.
/// </summary>
[TestClass]
public sealed class TestRunHooks
{
    /// <summary>
    /// Puts back Windows settings that an interrupted earlier run left changed
    /// (see <see cref="IOsSettings"/>). Fails the whole run, with the steps to
    /// fix it, when something cannot be put back automatically.
    /// </summary>
    [AssemblyInitialize]
    public static void RestoreLeftoverOsSettings(TestContext _)
    {
        if (RecordedSettings.ReadAll().Count == 0)
        {
            return;
        }

        using var automation = new UIA3Automation();
        var center = new FlaUiNotificationCenter(automation.GetDesktop());
        new FlaUiOsSettings(center).RestoreLeftovers();
    }
}
