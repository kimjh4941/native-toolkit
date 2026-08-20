using WindowsLibraryExampleUITest.Infra;

namespace WindowsLibraryExampleUITest.Pages;

/// <summary>
/// The clipboard sample page.
/// </summary>
/// <remarks>
/// Every operation reports through a single result line in the fixed shape
/// "[method] errorCode=N", which is what the assertions key off. Presses are
/// followed by a wait on that line rather than a sleep, because the page runs
/// its clipboard work on the thread pool.
/// </remarks>
public sealed class ClipboardPage
{
    private const string ResultId = "ResultTextBlock";
    private const string LogId = "LogTextBlock";
    private static readonly TimeSpan ResultTimeout = TimeSpan.FromSeconds(15);

    private readonly IUiSession _session;

    public ClipboardPage(IUiSession session) => _session = session;

    public string ResultText => _session.WaitForElement(ResultId).Text;

    public string LogText => _session.WaitForElement(LogId).Text;

    /// <summary>Returns to the main menu. The page is recreated on re-entry.</summary>
    public MainMenuPage GoBack()
    {
        Press("BackButton");

        var menu = new MainMenuPage(_session);
        menu.WaitUntilShown();
        return menu;
    }

    /// <summary>Presses InitializeManager and waits for it to report success.</summary>
    public ClipboardPage Initialize()
    {
        Press("InitializeManager");
        WaitFor(ResultMarker("InitializeManager", 0));
        return this;
    }

    /// <summary>Presses Uninitialize and waits for the teardown to complete.</summary>
    public ClipboardPage Uninitialize()
    {
        Press("Uninitialize");
        WaitFor(ResultMarker("Uninitialize", 0));
        return this;
    }

    public void Press(string automationId) => _session.WaitForElement(automationId).Invoke();

    /// <summary>
    /// Presses a button and waits until the result line reports the given method
    /// and error code. Returns the full result text so a failure can show it.
    /// </summary>
    public string PressAndExpect(string automationId, string method, int expectedErrorCode)
        => PressAndWaitFor(automationId, ResultMarker(method, expectedErrorCode));

    /// <summary>
    /// Presses a button and waits until the result line contains the fragment.
    /// Used where the outcome is not reported in the "errorCode=N" shape, such as
    /// the guards that refuse to call the bridge at all.
    /// </summary>
    public string PressAndWaitFor(string automationId, string fragment)
    {
        Press(automationId);
        return WaitFor(fragment);
    }

    public string WaitFor(string fragment)
        => _session.WaitForText(ResultId, text => text.Contains(fragment, StringComparison.Ordinal), ResultTimeout);

    /// <summary>
    /// Waits for a fragment in the log area.
    /// </summary>
    /// <remarks>
    /// The result line only holds the latest outcome and is overwritten as soon as
    /// a pending callback completes, so anything that has to survive a sequence of
    /// events must be read from the log, which is append-only.
    /// </remarks>
    public string WaitForLog(string fragment)
        => _session.WaitForText(LogId, text => text.Contains(fragment, StringComparison.Ordinal), ResultTimeout);

    public static string ResultMarker(string method, int errorCode) => $"[{method}] errorCode={errorCode}";
}
