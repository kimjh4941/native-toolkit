using WindowsLibraryExampleUITest.Infra;

namespace WindowsLibraryExampleUITest.Pages;

/// <summary>
/// The dialog sample page.
/// </summary>
/// <remarks>
/// Every button opens a modal dialog on the UI thread and writes the outcome
/// to the result line after the dialog closes. The buttons are therefore
/// clicked, not invoked (see <see cref="IUiElement.Click"/>).
/// </remarks>
public sealed class DialogPage
{
    private const string ResultId = "ResultTextBlock";
    private static readonly TimeSpan ResultTimeout = TimeSpan.FromSeconds(15);

    /// <summary>Win32 control ids inside the dialogs.</summary>
    public static class Controls
    {
        /// <summary>OK in a message box; Open, Save or Select Folder in a file dialog.</summary>
        public const string Accept = "1";

        public const string Cancel = "2";

        /// <summary>File name box of the open-file dialog.</summary>
        public const string OpenFileName = "1148";

        /// <summary>File name box of the save dialog.</summary>
        public const string SaveFileName = "1001";

        /// <summary>Folder box of the folder dialog.</summary>
        public const string FolderName = "1152";
    }

    private readonly IUiSession _session;

    public DialogPage(IUiSession session) => _session = session;

    public string ResultText => _session.WaitForElement(ResultId).Text;

    /// <summary>Clicks a sample button and returns the dialog it opens.</summary>
    public IUiDialog Open(string automationId)
    {
        _session.WaitForElement(automationId).Click();
        return _session.WaitForDialog();
    }

    /// <summary>Waits until the result line contains the fragment.</summary>
    public string WaitForResult(string fragment)
        => _session.WaitForText(ResultId, text => text.Contains(fragment, StringComparison.Ordinal), ResultTimeout);

    /// <summary>Returns to the main menu.</summary>
    public MainMenuPage GoBack()
    {
        _session.WaitForElement("BackButton").Invoke();

        var menu = new MainMenuPage(_session);
        menu.WaitUntilShown();
        return menu;
    }
}
