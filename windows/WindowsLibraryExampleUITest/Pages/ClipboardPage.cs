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
    private static readonly TimeSpan ResultTimeout = TimeSpan.FromSeconds(15);

    private readonly IUiSession _session;

    public ClipboardPage(IUiSession session) => _session = session;

    public string ResultText => _session.WaitForElement(ResultId).Text;

    /// <summary>Presses InitializeManager and waits for it to report success.</summary>
    public ClipboardPage Initialize()
    {
        Press("InitializeManager");
        WaitForResult("InitializeManager", expectedErrorCode: 0);
        return this;
    }

    /// <summary>Presses Uninitialize and waits for the teardown to complete.</summary>
    public ClipboardPage Uninitialize()
    {
        Press("Uninitialize");
        WaitForResult("Uninitialize", expectedErrorCode: 0);
        return this;
    }

    public void Press(string automationId) => _session.WaitForElement(automationId).Invoke();

    /// <summary>
    /// Presses a button and waits until the result line reports the given method
    /// and error code. Returns the full result text so a failure can show it.
    /// </summary>
    public string PressAndExpect(string automationId, string method, int expectedErrorCode)
    {
        Press(automationId);
        return WaitForResult(method, expectedErrorCode);
    }

    private string WaitForResult(string method, int expectedErrorCode)
    {
        var marker = $"[{method}] errorCode={expectedErrorCode}";
        return _session.WaitForText(ResultId, text => text.Contains(marker, StringComparison.Ordinal), ResultTimeout);
    }
}
