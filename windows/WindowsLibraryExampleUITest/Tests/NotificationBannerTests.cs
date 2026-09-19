using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers notification banners (N-21, N-22).
/// </summary>
/// <remarks>
/// Banners never appear while Do Not Disturb is on, so each test turns it off
/// and the scope puts it back. While it is off, other apps' banners can appear
/// too; only the sample app's are matched.
/// </remarks>
[TestClass]
[TestCategory("NotificationBanner")]
public sealed class NotificationBannerTests
{
    private static readonly TimeSpan BannerLifetime = TimeSpan.FromSeconds(15);

    private IUiSession? _session;
    private NotificationPage? _page;

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _page = new MainMenuPage(_session).OpenNotificationSample().Initialize().RemoveAll();
    }

    [TestCleanup]
    public void Teardown()
    {
        try
        {
            _page?.Press("RemoveAll");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Notification cleanup: {ex.Message}");
        }
        _session?.Dispose();
        _session = null;
        _page = null;
    }

    private IUiSession Session => _session ?? throw new InvalidOperationException("Setup did not run.");

    private NotificationPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    /// <summary>N-21</summary>
    [TestMethod]
    public void ShowBasic_ShowsABannerThatGoesAway()
    {
        using (Session.OsSettings.TurnOffDoNotDisturb())
        {
            Page.PressAndExpect("ShowBasic", "ShowBasic", 0);

            var banner = Session.Banners.WaitFor("Hello")
                ?? throw new AssertFailedException("No banner titled 'Hello' appeared.");
            Assert.AreEqual("Basic toast", banner.Body);
            Assert.IsTrue(Session.Banners.WaitUntilGone("Hello", BannerLifetime), "The banner did not go away.");
        }
    }

    /// <summary>N-22</summary>
    [TestMethod]
    public void PressingOpenOnTheBanner_DeliversItsArguments()
    {
        using (Session.OsSettings.TurnOffDoNotDisturb())
        {
            Page.PressAndExpect("ShowWithButtons", "ShowWithButtons", 0);

            var banner = Session.Banners.WaitFor("Actionable")
                ?? throw new AssertFailedException("No banner titled 'Actionable' appeared.");
            banner.PressAction("Open");

            StringAssert.Contains(Page.WaitFor(NotificationPage.Invoked), "\"action\":\"open\"");
        }
    }
}
