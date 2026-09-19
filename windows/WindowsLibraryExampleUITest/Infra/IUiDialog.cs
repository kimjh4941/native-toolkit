namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// A modal Win32 dialog opened by the app: a message box or a common file or
/// folder dialog.
/// </summary>
/// <remarks>
/// Controls are addressed by their Win32 control id, which UI Automation
/// exposes as the AutomationId. Unlike the button captions, which follow the
/// display language, the ids stay the same.
/// </remarks>
public interface IUiDialog
{
    /// <summary>The dialog's window title.</summary>
    string Title { get; }

    /// <summary>Replaces the text of the edit control with the given control id.</summary>
    void SetText(string controlId, string text);

    /// <summary>Presses the button with the given control id.</summary>
    /// <remarks>
    /// Accepts split buttons too: "Open" in the open-file dialog is one.
    /// </remarks>
    void Press(string controlId);

    /// <summary>True once the dialog window has closed.</summary>
    bool WaitUntilClosed(TimeSpan? timeout = null);
}
