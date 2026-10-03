namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Notification banners (the pop-up in the corner of the screen).
/// </summary>
/// <remarks>
/// Banners only appear while Do Not Disturb is off (see
/// <see cref="IOsSettings.TurnOffDoNotDisturb"/>). Other apps' banners may
/// show up at the same time; only the sample app's are matched.
/// </remarks>
public interface IBanners
{
    /// <summary>
    /// Waits for the app's banner with the given title. Returns null when it
    /// does not appear in time.
    /// </summary>
    /// <remarks>
    /// The banner slides in; <see cref="INotificationItem.PressAction"/> waits
    /// for the button to stop moving, because a press during the animation is
    /// ignored.
    /// </remarks>
    INotificationItem? WaitFor(string title, TimeSpan? timeout = null);

    /// <summary>True when the banner is gone within the timeout.</summary>
    bool WaitUntilGone(string title, TimeSpan timeout);
}
