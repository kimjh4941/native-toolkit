namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Windows settings that some tests have to change.
/// </summary>
/// <remarks>
/// Each method changes the setting and returns a scope; disposing the scope
/// puts the original value back and checks that it took. The original value
/// is also written to a file before anything is changed, so a run that is
/// killed half way is repaired at the start of the next one (see
/// <see cref="TestRunHooks"/>).
/// </remarks>
public interface IOsSettings
{
    /// <summary>
    /// Turns Do Not Disturb off so that banners appear. Does nothing (and the
    /// scope restores nothing) when it is already off.
    /// </summary>
    IDisposable TurnOffDoNotDisturb();

    /// <summary>
    /// Switches the sample app's notifications off in Settings. They must be on
    /// to begin with; the call fails otherwise.
    /// </summary>
    /// <remarks>
    /// The Settings page shows the switch Off until it has loaded, so there is
    /// no reliable "already off" reading; the switch is only touched once it
    /// shows On.
    /// Needs at least one of the app's notifications in the notification centre:
    /// the Settings page is reached through that notification group's menu.
    /// Any running Settings instance is closed first; Settings is
    /// single-instance, and an instance on another virtual desktop is hidden
    /// from UI Automation.
    /// </remarks>
    IDisposable TurnOffAppNotifications();
}
