using WindowsLibraryExampleUITest.Infra;

namespace WindowsLibraryExampleUITest.Pages;

/// <summary>The menu the app shows on startup.</summary>
public sealed class MainMenuPage
{
    private readonly IUiSession _session;

    public MainMenuPage(IUiSession session) => _session = session;

    /// <summary>Waits until the menu is on screen (used after a Back press).</summary>
    public void WaitUntilShown() => _session.WaitForElement("ClipboardCard");

    public ClipboardPage OpenClipboardSample()
    {
        _session.WaitForElement("ClipboardCard").Invoke();

        // The result line only exists on the clipboard page, so waiting for it
        // confirms the navigation finished before any test touches a button.
        _session.WaitForElement("ResultTextBlock");
        return new ClipboardPage(_session);
    }
}
