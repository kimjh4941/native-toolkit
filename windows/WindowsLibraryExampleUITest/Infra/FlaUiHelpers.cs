using System.Diagnostics;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Shared FlaUI helpers for the Infra layer.
/// </summary>
internal static class FlaUiHelpers
{
    public static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan StableTimeout = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Waits until the element's bounding rectangle is the same on two reads in
    /// a row, or the timeout elapses (the caller then acts at the last position).
    /// </summary>
    public static void WaitUntilStable(AutomationElement element)
    {
        var last = element.BoundingRectangle;
        var deadline = DateTime.UtcNow + StableTimeout;
        while (DateTime.UtcNow < deadline)
        {
            Thread.Sleep(PollInterval);
            var now = element.BoundingRectangle;
            if (now == last)
            {
                return;
            }
            last = now;
        }
    }

    /// <summary>
    /// Polls until the function returns non-null or the timeout elapses.
    /// Exceptions count as "not yet": shell elements disappear and reappear
    /// while they animate.
    /// </summary>
    public static T? WaitFor<T>(Func<T?> find, TimeSpan timeout) where T : class
    {
        var deadline = DateTime.UtcNow + timeout;
        do
        {
            var found = Safe(find, null);
            if (found is not null)
            {
                return found;
            }
            Thread.Sleep(PollInterval);
        }
        while (DateTime.UtcNow < deadline);
        return null;
    }

    /// <summary>Polls until the condition holds or the timeout elapses.</summary>
    public static bool WaitUntil(Func<bool> condition, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        do
        {
            if (Safe(condition, false))
            {
                return true;
            }
            Thread.Sleep(PollInterval);
        }
        while (DateTime.UtcNow < deadline);
        return false;
    }

    public static T Safe<T>(Func<T> read, T fallback)
    {
        try
        {
            return read();
        }
        catch
        {
            return fallback;
        }
    }

    public static string Name(AutomationElement e) => Safe(() => e.Properties.Name.ValueOrDefault ?? string.Empty, string.Empty);

    public static string ClassName(AutomationElement e) => Safe(() => e.Properties.ClassName.ValueOrDefault ?? string.Empty, string.Empty);

    public static string ProcessName(AutomationElement e) =>
        Safe(() => Process.GetProcessById(e.Properties.ProcessId.ValueOrDefault).ProcessName, string.Empty);

    /// <summary>Top-level windows owned by the given process.</summary>
    public static IEnumerable<AutomationElement> WindowsOf(AutomationElement desktop, string processName) =>
        Safe(() => desktop.FindAllChildren(), Array.Empty<AutomationElement>())
            .Where(w => ProcessName(w) == processName);

    /// <summary>Invokes the element, or clicks it when it has no Invoke pattern.</summary>
    public static void Invoke(AutomationElement element)
    {
        if (element.Patterns.Invoke.IsSupported)
        {
            element.Patterns.Invoke.Pattern.Invoke();
            return;
        }
        element.Click();
    }

    public static void PressEscape() => Keyboard.Type(VirtualKeyShort.ESCAPE);

    public static void PressWinN() => Keyboard.TypeSimultaneously(VirtualKeyShort.LWIN, VirtualKeyShort.KEY_N);

    public static bool IsExpandable(AutomationElement e) =>
        e.Patterns.ExpandCollapse.IsSupported &&
        e.Patterns.ExpandCollapse.Pattern.ExpandCollapseState.ValueOrDefault == ExpandCollapseState.Collapsed;
}
