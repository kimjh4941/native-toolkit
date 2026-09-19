using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the notification sample page (N-01 to N-20 and N-23 in
/// artifact/topics/windows-architecture/designs/2026-09-19-windows-architecture-ui-test-design.md).
/// Banners (N-21, N-22) are in <see cref="NotificationBannerTests"/>.
/// </summary>
/// <remarks>
/// What a notification shows is checked in the notification centre, which
/// keeps it regardless of banners and Do Not Disturb. Whether it exists at all
/// is checked through GetAllNotifications, which is exact and does not depend
/// on the shell.
/// The Show buttons share the tag "sample", so a new notification replaces the
/// previous one; each test therefore checks a single kind and starts from an
/// empty list.
/// </remarks>
[TestClass]
[TestCategory("Notification")]
public sealed class NotificationTests
{
    private static readonly TimeSpan ExpiryWait = TimeSpan.FromSeconds(25);
    private static readonly TimeSpan ScheduleWait = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan SettingWait = TimeSpan.FromSeconds(15);

    private IUiSession? _session;
    private NotificationPage? _page;

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _page = new MainMenuPage(_session).OpenNotificationSample();
    }

    [TestCleanup]
    public void Teardown()
    {
        if (_session is not null)
        {
            try
            {
                // Leave nothing behind for the next test or the user.
                _session.NotificationCenter.Close();
                _page?.Press("RemoveAll");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Notification cleanup: {ex.Message}");
            }
        }
        _session?.Dispose();
        _session = null;
        _page = null;
    }

    private IUiSession Session => _session ?? throw new InvalidOperationException("Setup did not run.");

    private NotificationPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    /// <summary>Initialized, with no notifications left from earlier runs.</summary>
    private NotificationPage Ready() => Page.Initialize().RemoveAll();

    private INotificationItem FindInCentre(string title) =>
        Session.NotificationCenter.Find(title)
        ?? throw new AssertFailedException($"The notification '{title}' did not appear in the notification centre.");

    /// <summary>N-01</summary>
    [TestMethod]
    public void Initialize_ReportsNotificationsEnabled()
    {
        Page.PressAndWaitFor("InitializeManager", "[InitializeManager] initialized. setting=0");
    }

    /// <summary>N-02</summary>
    [TestMethod]
    public void GetSetting_ReportsEnabled()
    {
        Ready();

        Page.PressAndWaitFor("GetSetting", "[GetSetting] Enabled");
    }

    /// <summary>N-03</summary>
    [TestMethod]
    public void ShowBasic_AppearsWithItsTitleAndBody()
    {
        Ready().PressAndExpect("ShowBasic", "ShowBasic", 0);

        StringAssert.Contains(Page.GetAll(), "count=1");
        var item = FindInCentre("Hello");
        Assert.AreEqual("Basic toast", item.Body);
    }

    /// <summary>N-04</summary>
    [TestMethod]
    public void ShowWithButtons_PressingOpen_DeliversItsArguments()
    {
        Ready().PressAndExpect("ShowWithButtons", "ShowWithButtons", 0);

        var item = FindInCentre("Actionable");
        item.Expand();
        item.PressAction("Open");

        var result = Page.WaitFor(NotificationPage.Invoked);
        StringAssert.Contains(result, "\"action\":\"open\"");
    }

    /// <summary>N-05</summary>
    [TestMethod]
    public void ShowWithInput_SendingTheReply_DeliversTheInputs()
    {
        Ready().PressAndExpect("ShowWithInput", "ShowWithInput", 0);

        var item = FindInCentre("Reply");
        item.Expand();
        item.SetInput("ui-test-reply");
        item.SelectOption("Free");
        item.PressAction("Send");

        var result = Page.WaitFor(NotificationPage.Invoked);
        StringAssert.Contains(result, "\"action\":\"send\"");
        StringAssert.Contains(result, "\"reply\":\"ui-test-reply\"");
        StringAssert.Contains(result, "\"opt\":\"free\"");
    }

    /// <summary>N-06 (which image is shown is checked by computer use, CU-01)</summary>
    [TestMethod]
    public void ShowWithImage_ShowsAnImage()
    {
        Ready().PressAndExpect("ShowWithImage", "ShowWithImage", 0);

        var item = FindInCentre("With Image");
        item.Expand();
        Assert.IsTrue(item.HasImage, "The notification has no image element.");
    }

    /// <summary>N-07</summary>
    [TestMethod]
    public void UpdateProgress_MovesTheBarFrom30To60()
    {
        Ready().PressAndExpect("ShowWithProgress", "ShowWithProgress", 0);
        Assert.AreEqual(30d, FindInCentre("Downloading").ProgressValue);
        Session.NotificationCenter.Close();

        Page.PressAndExpect("UpdateProgress", "UpdateProgress", 0);

        // Re-read after reopening: the value is checked as the centre shows it now.
        var updated = RereadUntil(() => FindInCentre("Downloading").ProgressValue, value => value == 60d);
        Assert.AreEqual(60d, updated);
    }

    /// <summary>N-08</summary>
    [TestMethod]
    public void UpdateProgress_WithoutAProgressNotification_ReportsNotFound()
    {
        Ready();

        Page.PressAndWaitFor("UpdateProgress", "No progress notification");
    }

    /// <summary>N-09</summary>
    /// <remarks>
    /// Judged by GetAllNotifications: the notification centre was seen to keep
    /// showing an expired notification after the API had dropped it.
    /// </remarks>
    [TestMethod]
    public void ShowWithExpiration_IsGoneAfterTenSeconds()
    {
        Ready().PressAndExpect("ShowWithExpiration", "ShowWithExpiration", 0);
        StringAssert.Contains(Page.GetAll(), "count=1");

        Page.WaitForGetAll(NotificationPage.NoActiveNotifications, ExpiryWait);
    }

    /// <summary>N-10 (the sound itself is out of scope)</summary>
    [TestMethod]
    public void ShowWithAudio_Appears()
    {
        Ready().PressAndExpect("ShowWithAudio", "ShowWithAudio", 0);

        Assert.AreEqual("Toast with reminder sound", FindInCentre("Reminder").Body);
    }

    /// <summary>N-11</summary>
    [TestMethod]
    public void ScheduleSoon_AppearsOnlyAfterItsTime()
    {
        Ready().PressAndExpect("ScheduleSoon", "ScheduleSoon", 0);
        StringAssert.Contains(Page.GetAll(), NotificationPage.NoActiveNotifications);

        Page.WaitForGetAll("count=1", ScheduleWait);
        Assert.AreEqual("Fires in ~5 seconds", FindInCentre("Scheduled").Body);
    }

    /// <summary>N-12</summary>
    [TestMethod]
    public void ScheduleSoon_ThenCancel_NeverAppears()
    {
        Ready().PressAndExpect("ScheduleSoon", "ScheduleSoon", 0);
        Page.PressAndExpect("CancelScheduled", "CancelScheduled", 0);

        // Well past the scheduled time.
        Thread.Sleep(TimeSpan.FromSeconds(8));
        StringAssert.Contains(Page.GetAll(), NotificationPage.NoActiveNotifications);
    }

    /// <summary>N-13</summary>
    [TestMethod]
    public void SetBadge_ShowsTheCount_AndClearBadgeRemovesIt()
    {
        Ready().PressAndExpect("SetBadge", "SetBadge(5)", 0);
        Session.Badge.WaitFor(badge => badge == "5");

        Page.PressAndExpect("ClearBadge", "ClearBadge", 0);
        Session.Badge.WaitFor(badge => badge is null);
    }

    /// <summary>N-14</summary>
    /// <remarks>
    /// The shell draws a glyph badge with an icon-font character, and "alert"
    /// is U+EDAD. The character belongs to the shell, not to this toolkit, so a
    /// Windows update may change it; the test then fails with the code point it
    /// saw instead of passing silently.
    /// </remarks>
    [TestMethod]
    public void SetBadgeGlyph_ShowsTheAlertGlyph_AndClearBadgeRemovesIt()
    {
        const string AlertGlyph = "\uEDAD";

        Ready().PressAndExpect("SetBadgeGlyph", "SetBadgeGlyph(alert)", 0);
        Session.Badge.WaitFor(badge => badge == AlertGlyph);

        Page.PressAndExpect("ClearBadge", "ClearBadge", 0);
        Session.Badge.WaitFor(badge => badge is null);
    }

    /// <summary>N-15</summary>
    [TestMethod]
    public void RemoveById_RemovesThatNotification()
    {
        Ready().PressAndExpect("ShowBasic", "ShowBasic", 0);

        // RemoveById targets the id captured by the latest GetAllNotifications.
        StringAssert.Contains(Page.GetAll(), "count=1");
        Page.PressAndWaitFor("RemoveById", "errorCode=0");
        StringAssert.Contains(Page.ResultText, "[RemoveById(");

        StringAssert.Contains(Page.GetAll(), NotificationPage.NoActiveNotifications);
    }

    /// <summary>N-16</summary>
    [TestMethod]
    public void RemoveByTag_RemovesTheTaggedNotification()
    {
        Ready().PressAndExpect("ShowBasic", "ShowBasic", 0);
        StringAssert.Contains(Page.GetAll(), "count=1");

        Page.PressAndExpect("RemoveByTag", "RemoveByTag(sample)", 0);

        StringAssert.Contains(Page.GetAll(), NotificationPage.NoActiveNotifications);
    }

    /// <summary>N-17</summary>
    [TestMethod]
    public void RemoveAll_RemovesEveryNotification()
    {
        Ready().PressAndExpect("ShowBasic", "ShowBasic", 0);
        StringAssert.Contains(Page.GetAll(), "count=1");

        Page.RemoveAll();

        StringAssert.Contains(Page.GetAll(), NotificationPage.NoActiveNotifications);
    }

    /// <summary>N-18</summary>
    [TestMethod]
    public void ShowAfterUninitialize_ReportsNotInitialized()
    {
        Ready().PressAndWaitFor("Uninitialize", "[Uninitialize] done");

        Page.PressAndWaitFor("ShowBasic", NotificationPage.NotInitialized);
    }

    /// <summary>N-19</summary>
    [TestMethod]
    public void ShowWithoutInitialize_ReportsNotInitialized()
    {
        Page.PressAndWaitFor("ShowBasic", NotificationPage.NotInitialized);
    }

    /// <summary>N-20</summary>
    /// <remarks>
    /// Switches the app's notifications off in Settings and back on. A
    /// notification has to be in the centre first: Settings is reached through
    /// the app group's menu there.
    /// </remarks>
    [TestMethod]
    public void ShowWhileTheAppsNotificationsAreOff_ReportsDisabled()
    {
        Ready().PressAndExpect("ShowBasic", "ShowBasic", 0);
        FindInCentre("Hello");

        using (Session.OsSettings.TurnOffAppNotifications())
        {
            Page.WaitForSetting("DisabledForApplication", SettingWait);
            Page.PressAndWaitFor("ShowBasic", "Notifications are disabled");
        }

        Page.WaitForSetting("Enabled", SettingWait);
    }

    /// <summary>N-23</summary>
    /// <remarks>
    /// The page is recreated on re-entry and registers itself as the callback
    /// target again, so the activation must be shown on the new page.
    /// </remarks>
    [TestMethod]
    public void AfterLeavingAndReentering_TheCallbackReachesTheNewPage()
    {
        Ready();
        _page = Page.GoBack().OpenNotificationSample();

        // The new page tracks its own "initialized" flag.
        Page.Initialize().PressAndExpect("ShowWithButtons", "ShowWithButtons", 0);
        var item = FindInCentre("Actionable");
        item.Expand();
        item.PressAction("Open");

        StringAssert.Contains(Page.WaitFor(NotificationPage.Invoked), "\"action\":\"open\"");
    }

    /// <summary>
    /// Re-reads a value until it satisfies the check or five seconds pass.
    /// The centre redraws an updated notification a moment after the update.
    /// </summary>
    private T RereadUntil<T>(Func<T> read, Func<T, bool> ok)
    {
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(5);
        var value = read();
        while (!ok(value) && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
            Session.NotificationCenter.Close();
            value = read();
        }
        return value;
    }
}
