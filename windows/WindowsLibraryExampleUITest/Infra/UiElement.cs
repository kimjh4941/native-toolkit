namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// A single automation element, exposed without any FlaUI type in the signature.
/// </summary>
/// <remarks>
/// Tests and page objects depend on this instead of FlaUI directly, so replacing
/// FlaUI with a raw UI Automation client later stays confined to the Infra layer.
/// </remarks>
public interface IUiElement
{
    string AutomationId { get; }

    /// <summary>Current text of the element (Name for read-only text blocks).</summary>
    string Text { get; }

    bool IsEnabled { get; }

    /// <summary>Performs the element's primary action (Invoke pattern).</summary>
    void Invoke();

    /// <summary>
    /// Clicks the element with the mouse once it has stopped moving.
    /// </summary>
    /// <remarks>
    /// Use this instead of <see cref="Invoke"/> for a button whose handler opens
    /// a modal dialog. An Invoke stays in progress inside the app until the
    /// dialog closes, and every further UI Automation call into the app then
    /// times out, including the ones needed to operate the dialog. A click only
    /// sends input and returns.
    /// Waiting for the element to stop moving matters right after a page
    /// navigation: the page slides in, and a position read mid-animation lands
    /// the click on a different button.
    /// </remarks>
    void Click();
}
