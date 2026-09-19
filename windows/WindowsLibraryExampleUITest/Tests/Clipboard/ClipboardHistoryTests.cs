using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Clipboard;

/// <summary>
/// Covers the "History" rows (8.3) of the Windows clipboard sample app plan,
/// except ClearUnpinnedHistory, which is in
/// <see cref="ClipboardHistoryDestructiveTests"/>.
/// </summary>
/// <remarks>
/// These run against the user's own clipboard history. Every check is made on
/// items the test itself adds, which become the newest entries. The history
/// result line shows the start of the history JSON, which may hold the user's
/// text, so it is never echoed: waits go through
/// <see cref="ClipboardPage.WaitForRedacted"/> and assertions use messages
/// that do not include it.
/// </remarks>
[TestClass]
[TestCategory("ClipboardHistory")]
public sealed class ClipboardHistoryTests
{
    private const string SampleText = "Hello from native-toolkit";
    private const string Added = "[History] a new item was added to the history";
    private const int HistoryDisabled = 10;

    private IUiSession? _session;
    private ClipboardPage? _page;
    private IDisposable? _history;

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _history = _session.OsSettings.SetClipboardHistory(true);
        _page = new MainMenuPage(_session).OpenClipboardSample().Initialize();
        _page.PressAndExpect("SetHistoryCallbacks", "SetHistoryCallbacks", 0);
    }

    [TestCleanup]
    public void Teardown()
    {
        try
        {
            _session?.Dispose();
        }
        finally
        {
            _history?.Dispose();
            _history = null;
            _session = null;
            _page = null;
        }
    }

    private IUiSession Session => _session ?? throw new InvalidOperationException("Setup did not run.");

    private ClipboardPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    private static string Marker() => "ntk-uitest-" + Guid.NewGuid().ToString("N")[..12];

    /// <summary>Copies as another program and waits until the history reports the new item.</summary>
    private string CopyIntoHistory()
    {
        var marker = Marker();
        var before = Page.LogCount(Added);
        Session.ExternalClipboard.WriteText(marker);
        Page.WaitForLogCount(Added, before + 1);
        return marker;
    }

    /// <summary>Presses GetClipboardHistory and returns the result line (not to be echoed).</summary>
    private string GetHistory()
    {
        Page.Press("GetClipboardHistory");
        return Page.WaitForRedacted("[GetClipboardHistory] errorCode=0");
    }

    private static bool FirstItemIs(string history, string text) =>
        history.Contains("[{\"id\":\"", StringComparison.Ordinal) &&
        history.IndexOf($"\"text\":\"{text}\"", StringComparison.Ordinal) is var at && at >= 0 &&
        history.IndexOf("},{", StringComparison.Ordinal) is var next && (next < 0 || at < next);

    /// <summary>Availability: matches the Windows setting</summary>
    [TestMethod]
    public void Availability_FollowsTheWindowsSetting()
    {
        Page.Press("GetHistoryAvailability");
        Page.WaitFor("\"historyEnabled\":true");

        using (Session.OsSettings.SetClipboardHistory(false))
        {
            Page.Press("GetHistoryAvailability");
            Page.WaitFor("\"historyEnabled\":false");
        }
    }

    /// <summary>disabled -> GetHistory: HISTORY_DISABLED</summary>
    [TestMethod]
    public void GetHistory_WhileHistoryIsOff_ReportsHistoryDisabled()
    {
        using (Session.OsSettings.SetClipboardHistory(false))
        {
            Page.Press("GetClipboardHistory");
            Page.WaitForRedacted(ClipboardPage.ResultMarker("GetClipboardHistory", HistoryDisabled));
        }
    }

    /// <summary>Set callbacks -> copy: event log</summary>
    [TestMethod]
    public void CopyByAnotherProgram_RaisesTheHistoryCallback()
    {
        CopyIntoHistory();
    }

    /// <summary>GetHistory callback: newest first, timestamp string</summary>
    [TestMethod]
    public void GetHistory_ListsTheNewestItemFirstWithAStringTimestamp()
    {
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);
        var newest = CopyIntoHistory();

        var history = GetHistory();

        Assert.IsTrue(FirstItemIs(history, newest), "The item copied last is not the first history entry.");
        Assert.IsTrue(
            System.Text.RegularExpressions.Regex.IsMatch(history, "\"timestamp\":\"[0-9]+\""),
            "The first entry's timestamp is not a decimal string.");
    }

    /// <summary>Restore callback -> Paste: restored content</summary>
    /// <remarks>
    /// RestoreHistoryItem uses the id of the first entry of the latest
    /// GetClipboardHistory. Copying something else after that makes the restore
    /// observable: the older item must come back.
    /// </remarks>
    [TestMethod]
    public void Restore_PutsAnOlderItemBackOnTheClipboard()
    {
        var older = CopyIntoHistory();
        Assert.IsTrue(FirstItemIs(GetHistory(), older), "The item to restore is not the first history entry.");
        CopyIntoHistory();

        Page.Press("RestoreHistoryItem");
        Page.WaitForRedacted(ClipboardPage.ResultMarker("RestoreHistoryItem", 0));

        // Either value is one of the test's own markers, so it is safe to show.
        Assert.AreEqual(older, Session.ExternalClipboard.ReadText(), "The restored item is not on the clipboard.");
    }

    /// <summary>Delete callback -> GetHistory: item gone</summary>
    [TestMethod]
    public void Delete_RemovesThatItem()
    {
        var doomed = CopyIntoHistory();
        Assert.IsTrue(FirstItemIs(GetHistory(), doomed), "The item to delete is not the first history entry.");

        Page.Press("DeleteHistoryItem");
        Page.WaitForRedacted(ClipboardPage.ResultMarker("DeleteHistoryItem", 0));

        Assert.IsFalse(GetHistory().Contains(doomed, StringComparison.Ordinal), "The deleted item is still in the history.");
    }

    /// <summary>SENSITIVE -> not in the history (what Win+V lists)</summary>
    [TestMethod]
    public void SensitiveCopy_IsNotAddedToTheHistory()
    {
        var last = CopyIntoHistory();
        var before = Page.LogCount(Added);

        Page.PressAndExpect("CopySensitive", "CopyPlainText (SENSITIVE)", 0);

        Thread.Sleep(TimeSpan.FromSeconds(3));
        Assert.AreEqual(before, Page.LogCount(Added), "A history item was added for a SENSITIVE copy.");
        var history = GetHistory();
        Assert.IsTrue(FirstItemIs(history, last), "The newest history entry is not the one before the SENSITIVE copy.");
        Assert.IsFalse(history.Contains("Sensitive sample value", StringComparison.Ordinal), "The SENSITIVE value is in the history.");
    }

    /// <summary>GetHistory -> Cancel: CANCELED or an earlier success, exactly once</summary>
    [TestMethod]
    public void GetHistoryThenCancel_CompletesExactlyOnce()
    {
        Page.Press("GetClipboardHistory");
        Page.Press("CancelLastRequest");

        const string completed = "[Request] completed id=";
        Page.WaitForLogCount(completed, 1);
        Thread.Sleep(TimeSpan.FromSeconds(2));
        Assert.AreEqual(1, Page.LogCount(completed), "The request completed more than once.");

        var log = Page.LogText;
        Assert.IsTrue(
            log.Contains("GetClipboardHistory error=15", StringComparison.Ordinal) ||
            log.Contains("GetClipboardHistory error=0", StringComparison.Ordinal),
            "The request ended with neither CANCELED nor success.");
    }
}
