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
    private static readonly TimeSpan NegativeObservationWindow = TimeSpan.FromSeconds(3);

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

    /// <summary>
    /// True when the fragment never appears in the log during the window.
    /// </summary>
    /// <remarks>
    /// Used for the contracts expressed as an absence, where reading the log once
    /// would pass simply because the unwanted entry had not arrived yet.
    /// </remarks>
    public bool LogStaysWithout(string fragment, TimeSpan? window = null)
        => _session.StaysFalse(
            LogId,
            text => text.Contains(fragment, StringComparison.Ordinal),
            window ?? NegativeObservationWindow);

    /// <summary>How many times the fragment appears in the log.</summary>
    /// <remarks>
    /// The log only grows, so "a new event arrived" is an increase in this
    /// count rather than the fragment being present at all.
    /// </remarks>
    public int LogCount(string fragment)
    {
        var log = LogText;
        var count = 0;
        for (var at = log.IndexOf(fragment, StringComparison.Ordinal); at >= 0;
             at = log.IndexOf(fragment, at + fragment.Length, StringComparison.Ordinal))
        {
            count++;
        }
        return count;
    }

    /// <summary>Waits until the fragment appears in the log at least <paramref name="count"/> times.</summary>
    public void WaitForLogCount(string fragment, int count)
    {
        var deadline = DateTime.UtcNow + ResultTimeout;
        while (LogCount(fragment) < count)
        {
            if (DateTime.UtcNow > deadline)
            {
                throw new InvalidOperationException(
                    $"'{fragment}' appeared {LogCount(fragment)} time(s) in the log, expected {count}, " +
                    $"within {ResultTimeout.TotalSeconds:0} seconds.");
            }
            Thread.Sleep(100);
        }
    }

    /// <summary>
    /// Waits for a fragment in the result line without ever echoing the line.
    /// </summary>
    /// <remarks>
    /// For clipboard history results: the line shows the start of the history
    /// JSON, which holds the user's own clipboard text. On failure only the
    /// first two lines ("[method] errorCode=N" and "count=N, first id=...") are
    /// reported.
    /// </remarks>
    public string WaitForRedacted(string fragment)
    {
        try
        {
            return _session.WaitForText(ResultId, text => text.Contains(fragment, StringComparison.Ordinal), ResultTimeout);
        }
        catch (InvalidOperationException)
        {
            var head = string.Join(" | ", ResultText.Split('\n').Take(2));
            throw new InvalidOperationException(
                $"The result did not contain '{fragment}' within {ResultTimeout.TotalSeconds:0} seconds. " +
                $"Result (history text omitted): {head}");
        }
    }

    public static string ResultMarker(string method, int errorCode) => $"[{method}] errorCode={errorCode}";
}
