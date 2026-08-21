using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the monitoring and deferred-rendering rows that complete inside the
/// app. The rows in the same section that need another application to paste are
/// left to manual verification.
/// </summary>
[TestClass]
public sealed class ClipboardMonitoringTests
{
    private const string MonitorLine = "[Monitor] clipboard content changed";

    private IUiSession? _session;
    private ClipboardPage? _page;

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _page = new MainMenuPage(_session).OpenClipboardSample().Initialize();
    }

    [TestCleanup]
    public void Teardown()
    {
        _session?.Dispose();
        _session = null;
        _page = null;
    }

    private ClipboardPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    [TestMethod]
    public void SelfCopy_DoesNotRaiseAChangeNotification()
    {
        // The watcher records its own writes so a copy made by this app does not
        // come back as an external change. Verified as an absence: the copy has
        // completed, so a notification for it would already have been logged.
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);

        Assert.IsFalse(
            Page.LogText.Contains(MonitorLine, StringComparison.Ordinal),
            "A self-write raised a change notification, which would loop back into the app.");
    }

    [TestMethod]
    public void ReservedFormats_AreEnumeratedWhileStillDeferred()
    {
        Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);

        // The formats are announced to the clipboard before any data exists, so
        // enumeration has to list them while rendering is still deferred.
        var formats = Page.PressAndExpect("GetClipboardFormats", "GetClipboardFormats", 0);

        StringAssert.Contains(formats, "HTML Format");
        StringAssert.Contains(formats, "CF_UNICODETEXT");
    }

    [TestMethod]
    public void ReservedFormat_IsReportedAsAvailable()
    {
        Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);

        var result = Page.PressAndExpect("HasFormat", "HasFormat (CF_UNICODETEXT)", 0);

        StringAssert.Contains(result, "returned TRUE");
    }
}
