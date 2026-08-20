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
}
