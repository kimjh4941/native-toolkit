namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// A running instance of the sample app that tests can drive.
/// </summary>
/// <remarks>
/// Every lookup is bounded by a timeout: automation elements appear
/// asynchronously and the sample runs its clipboard work on a thread pool, so a
/// fixed sleep would be either flaky or needlessly slow.
/// </remarks>
public interface IUiSession : IDisposable
{
    /// <summary>Finds an element by AutomationId, retrying until the timeout elapses.</summary>
    IUiElement WaitForElement(string automationId, TimeSpan? timeout = null);

    /// <summary>True when the element exists within the timeout.</summary>
    bool TryWaitForElement(string automationId, TimeSpan? timeout, out IUiElement? element);

    /// <summary>
    /// Watches the element for <paramref name="window"/> and reports whether the
    /// predicate stayed false the whole time.
    /// </summary>
    /// <remarks>
    /// Needed for "this must never appear" checks. Reading once straight after an
    /// action would pass simply because the unwanted value had not arrived yet.
    /// </remarks>
    bool StaysFalse(string automationId, Func<string, bool> predicate, TimeSpan window);

    /// <summary>
    /// Waits until the element's text satisfies <paramref name="predicate"/>.
    /// Returns the last observed text so a failure message can show it.
    /// </summary>
    string WaitForText(string automationId, Func<string, bool> predicate, TimeSpan? timeout = null);
}
