namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// The Windows notification centre (Win+N), limited to the sample app's own
/// notifications.
/// </summary>
/// <remarks>
/// Notifications are checked here rather than on the banner: the banner is
/// gone after about seven seconds and never shows while Do Not Disturb is on,
/// but the centre keeps the notification either way. The centre also lists
/// other apps' notifications; nothing outside the sample app's group is ever
/// read.
/// </remarks>
public interface INotificationCenter
{
    /// <summary>
    /// Opens the centre if it is closed and waits for the app's notification
    /// with the given title. Returns null when it does not show up in time.
    /// </summary>
    INotificationItem? Find(string title, TimeSpan? timeout = null);

    /// <summary>Closes the centre if it is open.</summary>
    void Close();
}

/// <summary>One of the app's notifications, in the centre or on a banner.</summary>
public interface INotificationItem
{
    string Title { get; }

    string Body { get; }

    /// <summary>True when the notification shows an image (which one is not visible to UI Automation).</summary>
    bool HasImage { get; }

    /// <summary>The progress bar value (0 to 100), or null when there is none.</summary>
    double? ProgressValue { get; }

    /// <summary>
    /// Expands the notification in the centre. Buttons, text boxes and
    /// selection boxes only exist once it is expanded. Does nothing on a banner.
    /// </summary>
    void Expand();

    /// <summary>Presses the notification button with the given caption.</summary>
    void PressAction(string caption);

    /// <summary>Types into the notification's text box.</summary>
    void SetInput(string text);

    /// <summary>Picks the option with the given label in the notification's selection box.</summary>
    void SelectOption(string label);
}
