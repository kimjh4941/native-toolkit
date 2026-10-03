using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Clipboard;

/// <summary>
/// ClearUnpinnedHistory (8.3, "Clear callback -> GetHistory").
/// </summary>
/// <remarks>
/// This deletes every unpinned item in the user's clipboard history, and that
/// cannot be undone. It only runs when NTK_UITEST_DESTRUCTIVE=1 is set, which
/// scripts/test_windows.ps1 does for -IncludeDestructive (decision U-6 in the
/// UI test design). The category alone is not enough: a plain "dotnet test"
/// with no filter would run it.
/// </remarks>
[TestClass]
[TestCategory("ClipboardHistoryDestructive")]
public sealed class ClipboardHistoryDestructiveTests
{
    private const string Added = "[History] a new item was added to the history";
    private const string OptInVariable = "NTK_UITEST_DESTRUCTIVE";

    private IUiSession? _session;
    private ClipboardPage? _page;
    private IDisposable? _history;

    [TestInitialize]
    public void Setup()
    {
        if (Environment.GetEnvironmentVariable(OptInVariable) != "1")
        {
            Assert.Inconclusive(
                $"Skipped: this clears the user's unpinned clipboard history. Set {OptInVariable}=1 to run it.");
        }

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

    /// <summary>Clear callback -> GetHistory: only pinned items remain</summary>
    /// <remarks>
    /// Pinning cannot be done from the sample, so this checks the unpinned side:
    /// the item the test added is gone.
    /// </remarks>
    [TestMethod]
    public void ClearUnpinned_RemovesTheUnpinnedItems()
    {
        var page = _page!;
        var marker = "ntk-uitest-" + Guid.NewGuid().ToString("N")[..12];
        var before = page.LogCount(Added);
        _session!.ExternalClipboard.WriteText(marker);
        page.WaitForLogCount(Added, before + 1);

        page.Press("ClearUnpinnedHistory");
        page.WaitForRedacted(ClipboardPage.ResultMarker("ClearUnpinnedHistory", 0));

        page.Press("GetClipboardHistory");
        var history = page.WaitForRedacted("[GetClipboardHistory] errorCode=0");
        Assert.IsFalse(history.Contains(marker, StringComparison.Ordinal), "An unpinned item survived ClearUnpinnedHistory.");
    }
}
