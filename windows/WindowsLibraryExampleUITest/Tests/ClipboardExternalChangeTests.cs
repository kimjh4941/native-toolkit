using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the "Monitoring / Deferred" rows (8.2) of the Windows clipboard
/// sample app plan that involve another program. The test process plays that
/// program (see <see cref="IExternalClipboard"/>).
/// </summary>
/// <remarks>
/// The deferred rendering cases switch clipboard history off: while it is on,
/// the history service renders every reserved format the moment it is
/// reserved, so "rendered only when pasted" cannot be observed.
/// </remarks>
[TestClass]
[TestCategory("Clipboard")]
public sealed class ClipboardExternalChangeTests
{
    private const string SampleText = "Hello from native-toolkit";
    private const string SampleHtmlFragment = "<b>Hello</b> from native-toolkit";
    private const string Changed = "[Monitor] clipboard content changed";
    private const string ProviderCalled = "[Provider]";

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

    private IUiSession Session => _session ?? throw new InvalidOperationException("Setup did not run.");

    private ClipboardPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    private static string Marker() => "ntk-uitest-" + Guid.NewGuid().ToString("N")[..12];

    /// <summary>Init -> external copy: change log</summary>
    [TestMethod]
    public void CopyByAnotherProgram_IsReported()
    {
        var before = Page.LogCount(Changed);

        Session.ExternalClipboard.WriteText(Marker());

        Page.WaitForLogCount(Changed, before + 1);
    }

    /// <summary>Uninit TRUE -> external copy: no notification</summary>
    [TestMethod]
    public void CopyByAnotherProgram_AfterUninitialize_IsNotReported()
    {
        Page.Uninitialize();
        var before = Page.LogCount(Changed);

        Session.ExternalClipboard.WriteText(Marker());

        Thread.Sleep(TimeSpan.FromSeconds(3));
        Assert.AreEqual(before, Page.LogCount(Changed), "A change was reported after Uninitialize.");
    }

    /// <summary>Reserve -> external paste: provider query / fill log</summary>
    [TestMethod]
    public void ReservedFormat_IsRenderedOnlyWhenAnotherProgramPastes()
    {
        using (Session.OsSettings.SetClipboardHistory(false))
        {
            Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);
            Assert.IsTrue(Page.LogStaysWithout(ProviderCalled), "The provider ran before anything was pasted.");

            Assert.AreEqual(SampleText, Session.ExternalClipboard.ReadText());

            Page.WaitForLog("[Provider] format=CF_UNICODETEXT phase=fill");
        }
    }

    /// <summary>Reserve -> app exit -> paste: WM_RENDERALLFORMATS keeps the content</summary>
    /// <remarks>
    /// The app must exit normally: it uninitializes the manager when its main
    /// window closes, and only then does Windows ask it to render everything.
    /// </remarks>
    [TestMethod]
    public void ReservedFormats_SurviveTheAppClosing()
    {
        using (Session.OsSettings.SetClipboardHistory(false))
        {
            Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);
            var other = Session.ExternalClipboard;

            Session.Dispose();
            _session = null;

            Assert.AreEqual(SampleText, other.ReadText());
            StringAssert.Contains(other.ReadHtml(), SampleHtmlFragment);
        }
    }

    /// <summary>Reserve -> external copy: reservation dropped</summary>
    [TestMethod]
    public void Reservation_IsDroppedWhenAnotherProgramCopies()
    {
        using (Session.OsSettings.SetClipboardHistory(false))
        {
            Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);
            var marker = Marker();

            Session.ExternalClipboard.WriteText(marker);

            StringAssert.Contains(Page.PressAndExpect("PastePlainText", "PastePlainText", 0), marker);
            Assert.AreEqual(0, Page.LogCount(ProviderCalled), "The provider ran for a reservation that was replaced.");
        }
    }
}
