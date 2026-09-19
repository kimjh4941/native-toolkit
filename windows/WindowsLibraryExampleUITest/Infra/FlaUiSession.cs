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
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(100);
    private const string DialogWindowClass = "#32770";

    private readonly Application _application;
    private readonly UIA3Automation _automation;
    private readonly Window _window;
    private readonly FlaUiNotificationCenter _notificationCenter;

    private FlaUiSession(Application application, UIA3Automation automation, Window window)
    {
        _application = application;
        _automation = automation;
        _window = window;

        var desktop = automation.GetDesktop();
        _notificationCenter = new FlaUiNotificationCenter(desktop);
        Banners = new FlaUiBanners(desktop);
        Badge = new FlaUiTaskbarBadge(desktop);
        OsSettings = new FlaUiOsSettings(_notificationCenter);
    }

    public INotificationCenter NotificationCenter => _notificationCenter;

    public IBanners Banners { get; }

    public ITaskbarBadge Badge { get; }

    public IOsSettings OsSettings { get; }

    public IExternalClipboard ExternalClipboard { get; } = new Win32ExternalClipboard();

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
        catch (Exception startupFailure)
        {
            // The app may already be running even though the window never appeared,
            // so make sure it is gone rather than leaking it into the next test.
            Exception? cleanupFailure = null;
            if (application is not null)
            {
                try
                {
                    EnsureExited(application);
                }
                catch (Exception ex)
                {
                    cleanupFailure = ex;
                }
            }

            automation?.Dispose();
            application?.Dispose();

            if (cleanupFailure is not null)
            {
                // Report both: the startup failure explains the test, the cleanup
                // failure warns that later tests are no longer isolated.
                throw new AggregateException(
                    "The app failed to start and could not be terminated afterwards.",
                    startupFailure,
                    cleanupFailure);
            }

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

    public IUiDialog WaitForDialog(TimeSpan? timeout = null)
    {
        // The process id is read from the main window: for a packaged app it is
        // the process that actually owns the windows.
        var processId = _window.Properties.ProcessId.ValueOrDefault;

        var found = Retry.While(
            () => Native.FindVisibleWindow(processId, DialogWindowClass),
            handle => handle == IntPtr.Zero,
            timeout ?? DefaultTimeout,
            PollInterval,
            throwOnTimeout: false);

        if (!found.Success || found.Result == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                $"No modal dialog (window class {DialogWindowClass}) appeared within " +
                $"{(timeout ?? DefaultTimeout).TotalSeconds:0} seconds.");
        }

        return new FlaUiDialog(_automation.FromHandle(found.Result), found.Result);
    }

    /// <summary>
    /// Watches the element for <paramref name="window"/> and reports whether the
    /// predicate stayed false the whole time.
    /// </summary>
    /// <remarks>
    /// Reading once straight after an action would pass simply because the
    /// unwanted value had not arrived yet, so this keeps polling for the window.
    /// </remarks>
    public bool StaysFalse(string automationId, Func<string, bool> predicate, TimeSpan window)
    {
        var target = WaitForElement(automationId);
        var deadline = DateTime.UtcNow + window;

        do
        {
            if (predicate(target.Text))
            {
                return false;
            }
            Thread.Sleep(PollInterval);
        }
        while (DateTime.UtcNow < deadline);

        return true;
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
            // A notification centre left open would take the next test's Win+N
            // as "close" (it toggles).
            try
            {
                _notificationCenter.Close();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"UI test cleanup: could not close the notification centre. {ex.Message}");
            }

            try
            {
                _application.Close();
            }
            catch (Exception ex)
            {
                // Asking politely is best effort; WaitForExit below decides whether
                // the process actually went away.
                Console.WriteLine($"UI test cleanup: Close() failed, falling back to Kill. {ex.Message}");
            }

            // Deliberately not caught: a surviving instance would be reused by the
            // next test, so this has to fail the run rather than be logged away.
            EnsureExited(_application);
        }
        finally
        {
            _automation.Dispose();
            _application.Dispose();
        }
    }

    /// <summary>
    /// Waits for the app to exit, killing it if it does not, and throws when it
    /// survives both. Shared by teardown and by the failed-startup path so a
    /// lingering instance can never be inherited by the next test.
    /// </summary>
    private static void EnsureExited(Application application)
    {
        if (WaitWhileRunning(application))
        {
            return;
        }

        application.Kill();

        if (!WaitWhileRunning(application))
        {
            throw new InvalidOperationException(
                "The sample app did not exit after Kill(). A lingering instance would " +
                "make the next test start from unexpected state.");
        }
    }

    private static bool WaitWhileRunning(Application application)
    {
        var deadline = DateTime.UtcNow + ExitTimeout;
        while (!application.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(PollInterval);
        }

        return application.HasExited;
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

        public void Click()
        {
            FlaUiHelpers.WaitUntilStable(_element);
            _element.Click();
        }
    }

    private sealed class FlaUiDialog : IUiDialog
    {
        private readonly AutomationElement _dialog;
        private readonly IntPtr _handle;

        public FlaUiDialog(AutomationElement dialog, IntPtr handle)
        {
            _dialog = dialog;
            _handle = handle;
        }

        public string Title => _dialog.Name ?? string.Empty;

        public void SetText(string controlId, string text)
        {
            var edit = Find(controlId, cf => cf.ByControlType(ControlType.Edit));
            if (!edit.Patterns.Value.IsSupported)
            {
                throw new InvalidOperationException($"Control '{controlId}' in the dialog does not accept text.");
            }
            edit.Patterns.Value.Pattern.SetValue(text);
        }

        public void Press(string controlId)
        {
            var button = Find(controlId, cf =>
                cf.ByControlType(ControlType.Button).Or(cf.ByControlType(ControlType.SplitButton)));
            button.Patterns.Invoke.Pattern.Invoke();
        }

        public bool WaitUntilClosed(TimeSpan? timeout = null)
        {
            var result = Retry.WhileTrue(
                () => Native.IsVisibleWindow(_handle),
                timeout ?? DefaultTimeout,
                PollInterval,
                throwOnTimeout: false);
            return result.Success;
        }

        private AutomationElement Find(
            string controlId,
            Func<FlaUI.Core.Conditions.ConditionFactory, FlaUI.Core.Conditions.ConditionBase> kind)
        {
            var found = Retry.WhileNull(
                () => _dialog.FindFirstDescendant(cf => cf.ByAutomationId(controlId).And(kind(cf))),
                DefaultTimeout,
                PollInterval,
                throwOnTimeout: false);

            return found.Success && found.Result is not null
                ? found.Result
                : throw new InvalidOperationException(
                    $"No control with id '{controlId}' in the dialog '{Title}' within " +
                    $"{DefaultTimeout.TotalSeconds:0} seconds.");
        }
    }
}
