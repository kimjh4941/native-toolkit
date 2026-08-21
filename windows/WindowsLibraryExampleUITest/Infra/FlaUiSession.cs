using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// FlaUI-backed implementation of <see cref="IUiSession"/>.
/// This is the only file that references FlaUI types.
/// </summary>
public sealed class FlaUiSession : IUiSession
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ExitTimeout = TimeSpan.FromSeconds(10);

    private readonly Application _application;
    private readonly UIA3Automation _automation;
    private readonly Window _window;

    private FlaUiSession(Application application, UIA3Automation automation, Window window)
    {
        _application = application;
        _automation = automation;
        _window = window;
    }

    /// <summary>Launches the packaged sample app and waits for its main window.</summary>
    public static FlaUiSession Launch(TimeSpan? windowTimeout = null)
    {
        var aumid = AppIdentity.ResolveAumid();

        Application? application = null;
        UIA3Automation? automation = null;
        try
        {
            application = Application.LaunchStoreApp(aumid);
            automation = new UIA3Automation();

            var window = application.GetMainWindow(automation, windowTimeout ?? DefaultTimeout)
                ?? throw new InvalidOperationException(
                    $"The app started from '{aumid}' but no main window appeared within " +
                    $"{(windowTimeout ?? DefaultTimeout).TotalSeconds:0} seconds.");

            return new FlaUiSession(application, automation, window);
        }
        catch
        {
            automation?.Dispose();
            application?.Dispose();
            throw;
        }
    }

    public IUiElement WaitForElement(string automationId, TimeSpan? timeout = null)
    {
        if (TryWaitForElement(automationId, timeout, out var element) && element is not null)
        {
            return element;
        }

        throw new InvalidOperationException(
            $"No automation element with AutomationId '{automationId}' appeared within " +
            $"{(timeout ?? DefaultTimeout).TotalSeconds:0} seconds.");
    }

    public bool TryWaitForElement(string automationId, TimeSpan? timeout, out IUiElement? element)
    {
        var found = Retry.WhileNull(
            () => _window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            timeout ?? DefaultTimeout,
            throwOnTimeout: false);

        element = found.Success && found.Result is not null ? new FlaUiElement(found.Result) : null;
        return element is not null;
    }

    public string WaitForText(string automationId, Func<string, bool> predicate, TimeSpan? timeout = null)
    {
        var target = WaitForElement(automationId, timeout);

        var last = target.Text;
        var result = Retry.WhileFalse(
            () =>
            {
                last = target.Text;
                return predicate(last);
            },
            timeout ?? DefaultTimeout,
            throwOnTimeout: false);

        if (!result.Success)
        {
            throw new InvalidOperationException(
                $"The text of '{automationId}' did not reach the expected state within " +
                $"{(timeout ?? DefaultTimeout).TotalSeconds:0} seconds. Last observed value: {last}");
        }

        return last;
    }

    /// <summary>Closes the app and waits for the process to actually exit.</summary>
    /// <remarks>
    /// For a packaged app Close() asks the main window to close and returns
    /// without waiting, so the next Launch could reactivate the still-running
    /// instance and inherit its state. Tests rely on a fresh process each time.
    /// </remarks>
    public void Dispose()
    {
        try
        {
            _application.Close();
            WaitForExit();
        }
        catch (Exception ex)
        {
            // Surfaced rather than swallowed: a lingering instance makes the next
            // test start from unexpected state.
            Console.WriteLine($"UI test cleanup: closing the app failed. {ex.Message}");
        }
        finally
        {
            _automation.Dispose();
            _application.Dispose();
        }
    }

    private void WaitForExit()
    {
        var deadline = DateTime.UtcNow + ExitTimeout;
        while (!_application.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (_application.HasExited)
        {
            return;
        }

        _application.Kill();

        deadline = DateTime.UtcNow + ExitTimeout;
        while (!_application.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!_application.HasExited)
        {
            throw new InvalidOperationException(
                "The sample app did not exit after Kill(). A lingering instance would " +
                "make the next test start from unexpected state.");
        }
    }

    private sealed class FlaUiElement : IUiElement
    {
        private readonly AutomationElement _element;

        public FlaUiElement(AutomationElement element) => _element = element;

        public string AutomationId => _element.AutomationId;

        public string Text => _element.Name ?? string.Empty;

        public bool IsEnabled => _element.IsEnabled;

        public void Invoke()
        {
            if (_element.Patterns.Invoke.IsSupported)
            {
                _element.Patterns.Invoke.Pattern.Invoke();
                return;
            }

            _element.Click();
        }
    }
}
