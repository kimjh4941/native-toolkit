using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>FlaUI implementation of <see cref="INotificationCenter"/>.</summary>
/// <remarks>
/// Element ids come from the stage 0a spike
/// (artifact/topics/windows-architecture/results/2026-09-19-windows-architecture-stage0a-spike-result.md).
/// </remarks>
internal sealed class FlaUiNotificationCenter : INotificationCenter
{
    private const string ShellProcess = "ShellExperienceHost";
    private const string ShellWindowClass = "Windows.UI.Core.CoreWindow";
    private static readonly TimeSpan OpenTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan DefaultFindTimeout = TimeSpan.FromSeconds(10);

    private readonly AutomationElement _desktop;

    public FlaUiNotificationCenter(AutomationElement desktop) => _desktop = desktop;

    public INotificationItem? Find(string title, TimeSpan? timeout = null)
    {
        Open();
        var item = FlaUiHelpers.WaitFor(() => FindItem(title), timeout ?? DefaultFindTimeout);
        var window = Window();
        return item is null || window is null
            ? null
            : new FlaUiNotificationItem(item, window, bodyId: "Content", pressWhenStable: false);
    }

    public void Close()
    {
        // Esc goes to the focused window, which is the centre while it is open.
        for (var attempt = 0; attempt < 3 && Window() is not null; attempt++)
        {
            FlaUiHelpers.PressEscape();
            FlaUiHelpers.WaitUntil(() => Window() is null, TimeSpan.FromSeconds(2));
        }
    }

    /// <summary>Opens the centre unless it is open already (Win+N toggles).</summary>
    internal void Open()
    {
        if (Window() is not null)
        {
            return;
        }
        FlaUiHelpers.PressWinN();
        if (FlaUiHelpers.WaitFor(Window, OpenTimeout) is null)
        {
            throw new InvalidOperationException("The notification centre did not open after Win+N.");
        }
    }

    /// <summary>
    /// The open centre, or null. Its window name changes between runs, and a
    /// banner lives in a shell window of the same class, so the centre is told
    /// apart by the Do Not Disturb button that only it has.
    /// </summary>
    internal AutomationElement? Window() =>
        FlaUiHelpers.WindowsOf(_desktop, ShellProcess)
            .FirstOrDefault(w => FlaUiHelpers.ClassName(w) == ShellWindowClass &&
                                 FlaUiHelpers.Safe(() => w.FindFirstDescendant(cf => cf.ByAutomationId("DoNotDisturbButton")), null) is not null);

    /// <summary>
    /// The sample app's group in the open centre: the group whose own title is
    /// the app's display name. The group's own label ("notifications from
    /// ...") follows the display language, the title does not.
    /// </summary>
    internal AutomationElement? AppGroup() =>
        Window()?.FindAllDescendants(cf => cf.ByControlType(ControlType.Group))
            .FirstOrDefault(g => g.FindFirstChild(cf =>
                cf.ByAutomationId("Title").And(cf.ByName(AppIdentity.DisplayName))) is not null);

    private AutomationElement? FindItem(string title) =>
        AppGroup()?.FindAllChildren(cf => cf.ByControlType(ControlType.ListItem))
            .FirstOrDefault(i => i.FindFirstChild(cf =>
                cf.ByAutomationId("Title").And(cf.ByName(title))) is not null);

    internal AutomationElement Desktop => _desktop;
}

/// <summary>FlaUI implementation of <see cref="IBanners"/>.</summary>
internal sealed class FlaUiBanners : IBanners
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(15);

    private readonly AutomationElement _desktop;

    public FlaUiBanners(AutomationElement desktop) => _desktop = desktop;

    public INotificationItem? WaitFor(string title, TimeSpan? timeout = null)
    {
        var hit = FlaUiHelpers.WaitFor(() => FindToast(title), timeout ?? DefaultTimeout);
        return hit is null
            ? null
            : new FlaUiNotificationItem(hit.Toast, hit.Window, bodyId: "MessageText", pressWhenStable: true);
    }

    public bool WaitUntilGone(string title, TimeSpan timeout)
    {
        // Two misses in a row: a single read can miss a banner that is being
        // re-laid out.
        var misses = 0;
        return FlaUiHelpers.WaitUntil(() =>
        {
            misses = FindToast(title) is null ? misses + 1 : 0;
            return misses >= 2;
        }, timeout);
    }

    /// <summary>
    /// The app's banner with the given title. Other apps' banners can be on
    /// screen at the same time, so the sender is matched too.
    /// </summary>
    private BannerHit? FindToast(string title)
    {
        foreach (var window in FlaUiHelpers.WindowsOf(_desktop, "ShellExperienceHost"))
        {
            var toast = FlaUiHelpers.Safe(() => window.FindAllDescendants(cf => cf.ByAutomationId("NormalToastView")), Array.Empty<AutomationElement>())
                .FirstOrDefault(t =>
                    t.FindFirstChild(cf => cf.ByAutomationId("SenderName").And(cf.ByName(AppIdentity.DisplayName))) is not null &&
                    t.FindFirstChild(cf => cf.ByAutomationId("Title").And(cf.ByName(title))) is not null);
            if (toast is not null)
            {
                return new BannerHit(toast, window);
            }
        }
        return null;
    }

    private sealed record BannerHit(AutomationElement Toast, AutomationElement Window);
}

/// <summary>A notification in the centre (<c>Content</c>) or on a banner (<c>MessageText</c>).</summary>
internal sealed class FlaUiNotificationItem : INotificationItem
{
    private static readonly TimeSpan ElementTimeout = TimeSpan.FromSeconds(5);

    private readonly AutomationElement _item;
    private readonly AutomationElement _window;
    private readonly string _bodyId;
    private readonly bool _pressWhenStable;

    public FlaUiNotificationItem(AutomationElement item, AutomationElement window, string bodyId, bool pressWhenStable)
    {
        _item = item;
        _window = window;
        _bodyId = bodyId;
        _pressWhenStable = pressWhenStable;
    }

    public string Title => Text("Title");

    public string Body => Text(_bodyId);

    public bool HasImage =>
        FlaUiHelpers.Safe(() => _item.FindFirstDescendant(cf => cf.ByControlType(ControlType.Image)) is not null, false);

    public double? ProgressValue
    {
        get
        {
            var bar = FlaUiHelpers.Safe(() => _item.FindFirstDescendant(cf => cf.ByAutomationId("progressBar")), null);
            return bar is not null && bar.Patterns.RangeValue.IsSupported
                ? bar.Patterns.RangeValue.Pattern.Value.ValueOrDefault
                : null;
        }
    }

    public void Expand()
    {
        if (!FlaUiHelpers.IsExpandable(_item))
        {
            return;
        }
        _item.Patterns.ExpandCollapse.Pattern.Expand();
        FlaUiHelpers.WaitUntil(() => !FlaUiHelpers.IsExpandable(_item), ElementTimeout);
    }

    public void PressAction(string caption)
    {
        var button = Require(
            () => _item.FindFirstDescendant(cf => cf.ByAutomationId("VerbButton").And(cf.ByName(caption))),
            $"button '{caption}'");
        if (_pressWhenStable)
        {
            FlaUiHelpers.WaitUntilStable(button);
        }
        FlaUiHelpers.Invoke(button);
    }

    public void SetInput(string text)
    {
        var edit = Require(() => _item.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit)), "text box");
        edit.Patterns.Value.Pattern.SetValue(text);
    }

    public void SelectOption(string label)
    {
        var combo = Require(() => _item.FindFirstDescendant(cf => cf.ByControlType(ControlType.ComboBox)), "selection box");
        combo.Patterns.ExpandCollapse.Pattern.Expand();

        // The drop-down may be hosted outside the notification item.
        var option = Require(
            () => combo.FindFirstDescendant(cf => cf.ByName(label)) ??
                  _window.FindFirstDescendant(cf => cf.ByControlType(ControlType.ListItem).And(cf.ByName(label))),
            $"option '{label}'");
        option.Patterns.SelectionItem.Pattern.Select();
    }

    private string Text(string automationId) =>
        FlaUiHelpers.Safe(() => _item.FindFirstDescendant(cf => cf.ByAutomationId(automationId))?.Name, null) ?? string.Empty;

    private AutomationElement Require(Func<AutomationElement?> find, string what) =>
        FlaUiHelpers.WaitFor(find, ElementTimeout)
        ?? throw new InvalidOperationException($"No {what} in the notification '{Title}'.");
}

/// <summary>FlaUI implementation of <see cref="ITaskbarBadge"/>.</summary>
internal sealed class FlaUiTaskbarBadge : ITaskbarBadge
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    // Resolving the AUMID starts PowerShell, so do it once.
    private static readonly Lazy<string> ButtonId = new(() => "Appid: " + AppIdentity.ResolveAumid());

    private readonly AutomationElement _desktop;

    public FlaUiTaskbarBadge(AutomationElement desktop) => _desktop = desktop;

    public string? WaitFor(Func<string?, bool> predicate, TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? DefaultTimeout);
        var buttonSeen = false;
        string? last = null;
        do
        {
            var button = FindAppButton();
            if (button is not null)
            {
                buttonSeen = true;
                // No BadgeText child means no badge; a glyph badge has an empty name.
                var badge = FlaUiHelpers.Safe(() => button.FindFirstChild(cf => cf.ByAutomationId("BadgeText")), null);
                last = badge is null ? null : FlaUiHelpers.Name(badge);
                if (predicate(last))
                {
                    return last;
                }
            }
            Thread.Sleep(FlaUiHelpers.PollInterval);
        }
        while (DateTime.UtcNow < deadline);

        throw new InvalidOperationException(buttonSeen
            ? $"The taskbar badge did not reach the expected state; last value: {Describe(last)}."
            : $"The sample app's taskbar button ({ButtonId.Value}) was not found.");
    }

    private AutomationElement? FindAppButton() =>
        FlaUiHelpers.Safe(() => _desktop.FindAllChildren()
            .Where(w => FlaUiHelpers.ClassName(w) == "Shell_TrayWnd")
            .Select(t => t.FindFirstDescendant(cf => cf.ByAutomationId(ButtonId.Value)))
            .FirstOrDefault(b => b is not null), null);

    /// <summary>
    /// Describes a badge value with its code points: a glyph badge is an icon
    /// font character that prints as nothing.
    /// </summary>
    internal static string Describe(string? badge) => badge is null
        ? "no badge"
        : $"\"{badge}\" ({string.Join(" ", badge.Select(c => $"U+{(int)c:X4}"))})";
}
