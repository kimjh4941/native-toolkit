using System.Diagnostics;
using System.Text.Json;
using Microsoft.Win32;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>FlaUI implementation of <see cref="IOsSettings"/>.</summary>
/// <remarks>
/// How each setting is switched was worked out before stage 0c; see appendix C
/// of artifact/topics/windows-architecture/designs/2026-09-19-windows-architecture-ui-test-design.md.
/// </remarks>
internal sealed class FlaUiOsSettings : IOsSettings
{
    private const string DoNotDisturbKey = "DoNotDisturb";
    private const string AppNotificationsKey = "AppNotifications";
    private const string ClipboardHistoryKey = "ClipboardHistory";
    private const string AbsentValue = "absent";
    private const string ClipboardKeyPath = @"Software\Microsoft\Clipboard";
    private const string ClipboardHistoryValue = "EnableClipboardHistory";
    private const string AppToggleId = "SystemSettings_Notifications_AppNotifications_ToggleSwitch";
    private static readonly TimeSpan ToggleTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan SettingsPageTimeout = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan HoldTime = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan PageLoadTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ClipboardClearTimeout = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan ClipboardQuietTime = TimeSpan.FromMilliseconds(500);

    private readonly FlaUiNotificationCenter _center;

    public FlaUiOsSettings(FlaUiNotificationCenter center) => _center = center;

    public IDisposable TurnOffDoNotDisturb()
    {
        if (ReadDoNotDisturb() == ToggleState.Off)
        {
            return new Scope(null);
        }

        RecordedSettings.Record(DoNotDisturbKey, "On");
        SetDoNotDisturb(ToggleState.Off);
        return new Scope(() =>
        {
            SetDoNotDisturb(ToggleState.On);
            RecordedSettings.Clear(DoNotDisturbKey);
        });
    }

    public IDisposable TurnOffAppNotifications()
    {
        var toggle = OpenAppNotificationPage();

        // The page shows the switch Off until it has loaded the stored value, so
        // an early Off says nothing. The notifications are expected to be on:
        // wait for the switch to show that before touching it.
        if (!FlaUiHelpers.WaitUntil(() => Read(toggle) == ToggleState.On, PageLoadTimeout))
        {
            CloseSettingsApp();
            throw new InvalidOperationException(
                "The sample app's notification switch in Settings never showed On. Either the app's " +
                "notifications are already off, or the Settings page did not finish loading.");
        }

        RecordedSettings.Record(AppNotificationsKey, "On");
        SetToggle(toggle, ToggleState.Off, "the app's notifications");
        return new Scope(() =>
        {
            // The page stays open while the scope is alive: once the app's
            // notifications are off, its group (and so the way to this page)
            // is gone from the notification centre.
            var again = FindAppToggle(TimeSpan.FromSeconds(10))
                ?? throw new InvalidOperationException(
                    "The Settings page for the sample app was closed while its notifications were off. " +
                    "Switch them back on by hand: Settings > System > Notifications > " + AppIdentity.DisplayName + ".");
            SetToggle(again, ToggleState.On, "the app's notifications");
            CloseSettingsApp();
            RecordedSettings.Clear(AppNotificationsKey);
        });
    }

    public IDisposable SetClipboardHistory(bool enabled)
    {
        var original = ReadClipboardHistory();
        var wanted = enabled ? 1 : 0;
        if (original == wanted)
        {
            return new Scope(null);
        }

        RecordedSettings.Record(ClipboardHistoryKey, original?.ToString() ?? AbsentValue);
        SwitchClipboardHistory(wanted);
        return new Scope(() =>
        {
            SwitchClipboardHistory(original);
            RecordedSettings.Clear(ClipboardHistoryKey);
        });
    }

    /// <summary>
    /// Writes the setting and returns once the clipboard has settled.
    /// </summary>
    /// <remarks>
    /// Switching history off makes Windows empty the clipboard within about half
    /// a second. Anything a test put on the clipboard in that window was seen to
    /// vanish, so wait for the clipboard to change (when switching off) and then
    /// to stay unchanged for a moment.
    /// </remarks>
    private static void SwitchClipboardHistory(int? value)
    {
        var before = Native.GetClipboardSequenceNumber();
        WriteClipboardHistory(value);

        if (value == 0)
        {
            FlaUiHelpers.WaitUntil(() => Native.GetClipboardSequenceNumber() != before, ClipboardClearTimeout);
        }

        var last = Native.GetClipboardSequenceNumber();
        var quietSince = DateTime.UtcNow;
        var deadline = DateTime.UtcNow + ClipboardClearTimeout;
        while (DateTime.UtcNow - quietSince < ClipboardQuietTime && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(FlaUiHelpers.PollInterval);
            var now = Native.GetClipboardSequenceNumber();
            if (now != last)
            {
                last = now;
                quietSince = DateTime.UtcNow;
            }
        }
    }

    /// <summary>
    /// Puts back what an interrupted run left changed. Called once at the start
    /// of every test run.
    /// </summary>
    public void RestoreLeftovers()
    {
        var recorded = RecordedSettings.ReadAll();

        if (recorded.TryGetValue(ClipboardHistoryKey, out var history))
        {
            SwitchClipboardHistory(history == AbsentValue ? null : int.Parse(history));
            RecordedSettings.Clear(ClipboardHistoryKey);
        }

        if (recorded.TryGetValue(DoNotDisturbKey, out var dnd) && dnd == "On")
        {
            SetDoNotDisturb(ToggleState.On);
            RecordedSettings.Clear(DoNotDisturbKey);
        }

        if (recorded.ContainsKey(AppNotificationsKey))
        {
            // Not repaired automatically: with the app's notifications off, the
            // page that switches them is no longer reachable from the centre.
            throw new InvalidOperationException(
                "An earlier test run was stopped while the sample app's notifications were switched off. " +
                "Switch them back on (Settings > System > Notifications > " + AppIdentity.DisplayName + "), " +
                $"then delete {RecordedSettings.FilePath} and run the tests again.");
        }
    }

    /// <summary>
    /// The EnableClipboardHistory value (1 on, 0 off), or null when it has
    /// never been set. Windows applies a change as soon as it is written.
    /// </summary>
    private static int? ReadClipboardHistory()
    {
        using var key = Registry.CurrentUser.OpenSubKey(ClipboardKeyPath);
        return key?.GetValue(ClipboardHistoryValue) as int?;
    }

    private static void WriteClipboardHistory(int? value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(ClipboardKeyPath);
        if (value is null)
        {
            key.DeleteValue(ClipboardHistoryValue, throwOnMissingValue: false);
        }
        else
        {
            key.SetValue(ClipboardHistoryValue, value.Value, RegistryValueKind.DWord);
        }
    }

    private ToggleState ReadDoNotDisturb()
    {
        _center.Open();
        try
        {
            return ReadSettled(DoNotDisturbButton(), "Do Not Disturb");
        }
        finally
        {
            _center.Close();
        }
    }

    private void SetDoNotDisturb(ToggleState wanted)
    {
        _center.Open();
        try
        {
            SetToggle(DoNotDisturbButton(), wanted, "Do Not Disturb");
        }
        finally
        {
            _center.Close();
        }
    }

    private AutomationElement DoNotDisturbButton() =>
        FlaUiHelpers.WaitFor(() => _center.Window()?.FindFirstDescendant(cf => cf.ByAutomationId("DoNotDisturbButton")), ToggleTimeout)
        ?? throw new InvalidOperationException("The Do Not Disturb button was not found in the notification centre.");

    /// <summary>
    /// Opens the app's own notification settings page through the app group's
    /// menu in the notification centre, and returns its main switch. The page
    /// occasionally did not open; the whole sequence is then tried once more.
    /// </summary>
    private AutomationElement OpenAppNotificationPage()
    {
        CloseSettingsApp();
        try
        {
            return OpenAppNotificationPageOnce();
        }
        catch (InvalidOperationException first)
        {
            Console.WriteLine($"Opening the app's notification settings failed once, retrying: {first.Message}");
            CloseSettingsApp();
            _center.Close();
            return OpenAppNotificationPageOnce();
        }
    }

    private AutomationElement OpenAppNotificationPageOnce()
    {
        _center.Open();
        var group = FlaUiHelpers.WaitFor(_center.AppGroup, TimeSpan.FromSeconds(10))
            ?? throw new InvalidOperationException(
                "The sample app has no notification in the notification centre. Show one before switching its notifications off.");

        // The group's settings button opens a menu, not Settings itself.
        var menuButton = group.FindFirstChild(cf => cf.ByAutomationId("SettingsButton"))
            ?? throw new InvalidOperationException("The app group has no settings button.");
        FlaUiHelpers.Invoke(menuButton);

        var goToSettings = FlaUiHelpers.WaitFor(
            () => FlaUiHelpers.WindowsOf(_center.Desktop, "ShellExperienceHost")
                .Select(w => w.FindFirstDescendant(cf => cf.ByAutomationId("GoToNotificationSettingsMenuItem")))
                .FirstOrDefault(e => e is not null),
            ToggleTimeout)
            ?? throw new InvalidOperationException("The app group's menu has no 'open notification settings' item.");
        FlaUiHelpers.Invoke(goToSettings);

        return FindAppToggle(SettingsPageTimeout)
            ?? throw new InvalidOperationException("The sample app's notification settings page did not open.");
    }

    private AutomationElement? FindAppToggle(TimeSpan timeout) =>
        FlaUiHelpers.WaitFor(
            () => FlaUiHelpers.WindowsOf(_center.Desktop, "ApplicationFrameHost")
                .Concat(FlaUiHelpers.WindowsOf(_center.Desktop, "SystemSettings"))
                .Select(w => w.FindFirstDescendant(cf => cf.ByAutomationId(AppToggleId)))
                .FirstOrDefault(e => e is not null),
            timeout);

    /// <summary>
    /// Switches the toggle and makes sure the new state holds.
    /// </summary>
    /// <remarks>
    /// The Settings page is found before it has finished loading. A switch
    /// flipped at that moment was seen to jump back when the page then showed
    /// the stored value, so the state is watched for a while and the switch is
    /// flipped again if it reverted.
    /// </remarks>
    private static void SetToggle(AutomationElement toggle, ToggleState wanted, string what)
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (ReadSettled(toggle, what) != wanted)
            {
                toggle.Patterns.Toggle.Pattern.Toggle();
            }
            if (!FlaUiHelpers.WaitUntil(() => Read(toggle) == wanted, ToggleTimeout))
            {
                continue;
            }

            // A failed read is not a revert: only a real opposite value counts.
            var reverted = FlaUiHelpers.WaitUntil(() => Read(toggle) is { } now && now != wanted, HoldTime);
            if (!reverted)
            {
                return;
            }
        }
        throw new InvalidOperationException($"Could not switch {what} to {wanted}: it did not stay there.");
    }

    /// <summary>
    /// The toggle's state, or null when it cannot be read yet.
    /// </summary>
    /// <remarks>
    /// Not ValueOrDefault: on a page that has just opened the read can fail, and
    /// the default is Off. Taking that at face value made "already off, nothing
    /// to do" out of a switch that was on.
    /// </remarks>
    private static ToggleState? Read(AutomationElement toggle) =>
        FlaUiHelpers.Safe<ToggleState?>(
            () => toggle.Patterns.Toggle.Pattern.ToggleState.TryGetValue(out var state) ? state : null,
            null);

    /// <summary>Waits until the toggle's state can be read, and returns it.</summary>
    private static ToggleState ReadSettled(AutomationElement toggle, string what)
    {
        ToggleState? state = null;
        FlaUiHelpers.WaitUntil(() => (state = Read(toggle)) is not null, ToggleTimeout);
        return state ?? throw new InvalidOperationException($"Could not read the state of {what}.");
    }

    /// <summary>
    /// Settings is single-instance; an instance left on another virtual desktop
    /// is cloaked and cannot be driven, so it is closed first. Settings are
    /// saved as they are changed, so nothing is lost.
    /// </summary>
    private static void CloseSettingsApp()
    {
        foreach (var process in Process.GetProcessesByName("SystemSettings"))
        {
            try
            {
                process.Kill();
                process.WaitForExit(5000);
            }
            catch (InvalidOperationException)
            {
                // Already exited.
            }
        }
    }

    private sealed class Scope : IDisposable
    {
        private Action? _restore;

        public Scope(Action? restore) => _restore = restore;

        public void Dispose()
        {
            var restore = _restore;
            _restore = null;
            restore?.Invoke();
        }
    }
}

/// <summary>
/// Settings changed by the tests, with the value to put back, kept in a file
/// so that an interrupted run can be repaired by the next one.
/// </summary>
internal static class RecordedSettings
{
    public static readonly string FilePath = Path.Combine(Path.GetTempPath(), "ntk-uitest-os-settings.json");

    public static Dictionary<string, string> ReadAll() =>
        File.Exists(FilePath)
            ? JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(FilePath)) ?? new()
            : new();

    public static void Record(string key, string originalValue)
    {
        var all = ReadAll();
        all[key] = originalValue;
        File.WriteAllText(FilePath, JsonSerializer.Serialize(all));
    }

    public static void Clear(string key)
    {
        var all = ReadAll();
        if (!all.Remove(key))
        {
            return;
        }
        if (all.Count == 0)
        {
            File.Delete(FilePath);
        }
        else
        {
            File.WriteAllText(FilePath, JsonSerializer.Serialize(all));
        }
    }
}
