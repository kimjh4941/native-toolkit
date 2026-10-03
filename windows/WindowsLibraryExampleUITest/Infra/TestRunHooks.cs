using FlaUI.UIA3;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Work done once per test run.
/// </summary>
[TestClass]
public sealed class TestRunHooks
{
    private static string? _userClipboardText;

    /// <summary>
    /// Puts back Windows settings that an interrupted earlier run left changed
    /// (see <see cref="IOsSettings"/>), then remembers the user's clipboard text.
    /// </summary>
    /// <remarks>
    /// Fails the whole run, with the steps to fix it, when a setting cannot be
    /// put back automatically.
    /// </remarks>
    [AssemblyInitialize]
    public static void BeforeRun(TestContext _)
    {
        if (RecordedSettings.ReadAll().Count > 0)
        {
            using var automation = new UIA3Automation();
            var center = new FlaUiNotificationCenter(automation.GetDesktop());
            new FlaUiOsSettings(center).RestoreLeftovers();
        }

        _userClipboardText = new Win32ExternalClipboard().ReadText();
    }

    /// <summary>
    /// Gives the user their clipboard text back. The tests overwrite the
    /// clipboard; other formats the user had cannot be restored.
    /// </summary>
    [AssemblyCleanup]
    public static void AfterRun()
    {
        if (_userClipboardText is not null)
        {
            new Win32ExternalClipboard().WriteText(_userClipboardText);
        }
    }
}
