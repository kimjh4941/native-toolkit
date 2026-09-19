using WindowsLibraryExampleUITest.Infra;

namespace WindowsLibraryExampleUITest.Pages;

/// <summary>
/// The notification sample page.
/// </summary>
/// <remarks>
/// Every button reports on a single result line, mostly in the shape
/// "[method] errorCode=N". The same button can produce the same text twice in
/// a row, so a changed line alone does not prove the press happened; see
/// <see cref="PressAndWaitFor"/>.
/// </remarks>
public sealed class NotificationPage
{
    public const string NoActiveNotifications = "No active notifications";
    public const string NotInitialized = "Not initialized";
    public const string Invoked = "Notification invoked";

    private const string ResultId = "ResultTextBlock";
    private static readonly TimeSpan ResultTimeout = TimeSpan.FromSeconds(15);

    private readonly IUiSession _session;

    public NotificationPage(IUiSession session) => _session = session;

    public string ResultText => _session.WaitForElement(ResultId).Text;

    /// <summary>Presses InitializeManager and waits until it reports success.</summary>
    public NotificationPage Initialize()
    {
        PressAndWaitFor("InitializeManager", "[InitializeManager] initialized");
        return this;
    }

    /// <summary>Removes every notification the app has shown.</summary>
    public NotificationPage RemoveAll()
    {
        PressAndExpect("RemoveAll", "RemoveAll", 0);
        return this;
    }

    public void Press(string automationId) => _session.WaitForElement(automationId).Invoke();

    /// <summary>
    /// Presses a button and waits until the result line contains the fragment.
    /// </summary>
    /// <remarks>
    /// When the line already contains the fragment, a harmless button is pressed
    /// first so the line changes; otherwise the old text would satisfy the wait
    /// before the press had any effect.
    /// </remarks>
    public string PressAndWaitFor(string automationId, string fragment)
    {
        if (ResultText.Contains(fragment, StringComparison.Ordinal))
        {
            var (resetButton, resetMarker) = automationId == "GetSetting"
                ? ("GetAllNotifications", "[GetAllNotifications]")
                : ("GetSetting", "[GetSetting]");
            Press(resetButton);
            _session.WaitForText(ResultId, text => text.Contains(resetMarker, StringComparison.Ordinal), ResultTimeout);
        }

        Press(automationId);
        return WaitFor(fragment);
    }

    /// <summary>Presses a button and waits for "[method] errorCode=N".</summary>
    public string PressAndExpect(string automationId, string method, int errorCode)
        => PressAndWaitFor(automationId, $"[{method}] errorCode={errorCode}");

    public string WaitFor(string fragment)
        => _session.WaitForText(ResultId, text => text.Contains(fragment, StringComparison.Ordinal), ResultTimeout);

    /// <summary>Presses GetAllNotifications and returns the result line.</summary>
    public string GetAll() => PressAndWaitFor("GetAllNotifications", "[GetAllNotifications]");

    /// <summary>
    /// Presses GetAllNotifications until its result contains the fragment.
    /// Used for changes that happen on their own (a scheduled notification
    /// firing, an expiring one going away).
    /// </summary>
    public string WaitForGetAll(string fragment, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        string last;
        do
        {
            last = GetAll();
            if (last.Contains(fragment, StringComparison.Ordinal))
            {
                return last;
            }
            Thread.Sleep(1000);
        }
        while (DateTime.UtcNow < deadline);

        throw new InvalidOperationException(
            $"GetAllNotifications did not report '{fragment}' within {timeout.TotalSeconds:0} seconds. Last: {last}");
    }

    /// <summary>
    /// Presses GetSetting until it reports the given setting.
    /// </summary>
    /// <remarks>
    /// After the app's notifications are switched in Settings, the value the
    /// app reads changes a moment later; a single press can still see the old
    /// value, and waiting on that one result would never see the new one.
    /// </remarks>
    public string WaitForSetting(string setting, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        string last;
        do
        {
            last = PressAndWaitFor("GetSetting", "[GetSetting]");
            if (last.Contains($"[GetSetting] {setting}", StringComparison.Ordinal))
            {
                return last;
            }
            Thread.Sleep(500);
        }
        while (DateTime.UtcNow < deadline);

        throw new InvalidOperationException(
            $"GetSetting did not report '{setting}' within {timeout.TotalSeconds:0} seconds. Last: {last}");
    }

    /// <summary>Returns to the main menu. The page is recreated on re-entry.</summary>
    public MainMenuPage GoBack()
    {
        Press("BackButton");

        var menu = new MainMenuPage(_session);
        menu.WaitUntilShown();
        return menu;
    }
}
