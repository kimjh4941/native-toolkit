using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Dialog;

/// <summary>
/// Covers the dialog sample page: each of the six dialogs, accepted and
/// cancelled, plus returning to the menu and the overwrite confirmation (D-01 to D-14 in
/// artifact/topics/windows-architecture/designs/2026-09-19-windows-architecture-ui-test-design.md).
/// </summary>
/// <remarks>
/// Files and folders are picked by typing full paths into the dialog, so the
/// tests never depend on what the user's own folders contain. They live in a
/// temporary folder that is removed after the class runs.
/// </remarks>
[TestClass]
[TestCategory("Dialog")]
public sealed class DialogTests
{
    private static readonly string Work = Path.Combine(Path.GetTempPath(), "ntk-uitest-dialog");
    private static readonly string FileA = Path.Combine(Work, "a.txt");
    private static readonly string FileB = Path.Combine(Work, "b.txt");
    private static readonly string FolderA = Path.Combine(Work, "f1");
    private static readonly string FolderB = Path.Combine(Work, "f2");

    private IUiSession? _session;
    private DialogPage? _page;

    [ClassInitialize]
    public static void CreateTestFiles(TestContext _)
    {
        if (Directory.Exists(Work))
        {
            Directory.Delete(Work, recursive: true);
        }
        Directory.CreateDirectory(Work);
        File.WriteAllText(FileA, "a");
        File.WriteAllText(FileB, "b");
        Directory.CreateDirectory(FolderA);
        Directory.CreateDirectory(FolderB);
    }

    [ClassCleanup]
    public static void DeleteTestFiles()
    {
        // The common file dialogs move the app's current directory into the
        // folder they last showed, so the folder stays in use until the app
        // process has fully exited. Give it a few seconds rather than failing.
        for (var attempt = 1; Directory.Exists(Work); attempt++)
        {
            try
            {
                Directory.Delete(Work, recursive: true);
            }
            catch (IOException) when (attempt < 20)
            {
                Thread.Sleep(TimeSpan.FromMilliseconds(500));
            }
        }
    }

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _page = new MainMenuPage(_session).OpenDialogSample();
    }

    [TestCleanup]
    public void Teardown()
    {
        _session?.Dispose();
        _session = null;
        _page = null;
    }

    private DialogPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    /// <summary>D-01</summary>
    [TestMethod]
    public void Alert_Ok_ReturnsIdOk()
    {
        var dialog = Page.Open("ShowAlertDialog");
        Assert.AreEqual("Native Windows Dialog", dialog.Title);

        dialog.Press(DialogPage.Controls.Accept);

        Assert.IsTrue(dialog.WaitUntilClosed(), "The message box did not close.");
        Page.WaitForResult("ShowAlertDialog Result: 1");
    }

    /// <summary>D-02</summary>
    [TestMethod]
    public void Alert_Cancel_ReturnsIdCancel()
    {
        var dialog = Page.Open("ShowAlertDialog");

        dialog.Press(DialogPage.Controls.Cancel);

        Assert.IsTrue(dialog.WaitUntilClosed(), "The message box did not close.");
        Page.WaitForResult("ShowAlertDialog Result: 2");
    }

    /// <summary>D-03</summary>
    [TestMethod]
    public void OpenFile_Cancel_ReportsCanceled()
    {
        var dialog = Page.Open("ShowFileDialog");
        Assert.AreEqual("Open File", dialog.Title);

        dialog.Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowFileDialog was canceled.");
    }

    /// <summary>D-04</summary>
    [TestMethod]
    public void OpenFile_PickFile_ReturnsItsPath()
    {
        var dialog = Page.Open("ShowFileDialog");
        dialog.SetText(DialogPage.Controls.OpenFileName, FileA);
        dialog.Press(DialogPage.Controls.Accept);

        Page.WaitForResult($"ShowFileDialog Result: 1, filePath: {FileA}");
    }

    /// <summary>D-05</summary>
    [TestMethod]
    public void OpenMultipleFiles_Cancel_ReportsCanceled()
    {
        var dialog = Page.Open("ShowMultiFileDialog");
        Assert.AreEqual("Open Files", dialog.Title);

        dialog.Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowMultiFileDialog was canceled.");
    }

    /// <summary>D-06</summary>
    /// <remarks>
    /// Each file comes back as a full path and the count is the number of
    /// files, as with folders. The C ABI's folder-then-names layout, where two
    /// files report 3 (DLG-02), is joined by the C++ API (stage 3 design,
    /// OP-03); the sample shows the C++ API since stage 4.
    /// </remarks>
    [TestMethod]
    public void OpenMultipleFiles_PickTwo_ReturnsFullPaths()
    {
        var dialog = Page.Open("ShowMultiFileDialog");
        dialog.SetText(DialogPage.Controls.OpenFileName, $"\"{FileA}\" \"{FileB}\"");
        dialog.Press(DialogPage.Controls.Accept);

        var result = Page.WaitForResult("ShowMultiFileDialog Result: 2");
        StringAssert.Contains(result, $"multiBuffer[0]: {FileA}\n");
        StringAssert.Contains(result, $"multiBuffer[1]: {FileB}\n");
    }

    /// <summary>D-07</summary>
    [TestMethod]
    public void SaveFile_Cancel_ReportsCanceled()
    {
        var dialog = Page.Open("ShowSaveFileDialog");
        Assert.AreEqual("Save File", dialog.Title);

        dialog.Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowSaveFileDialog was canceled.");
    }

    /// <summary>D-08</summary>
    [TestMethod]
    public void SaveFile_NewName_ReturnsPathWithoutCreatingIt()
    {
        var target = Path.Combine(Work, "new.txt");

        var dialog = Page.Open("ShowSaveFileDialog");
        dialog.SetText(DialogPage.Controls.SaveFileName, target);
        dialog.Press(DialogPage.Controls.Accept);

        Page.WaitForResult($"ShowSaveFileDialog Result: 1, savePath: {target}");
        Assert.IsFalse(File.Exists(target), "The save dialog only picks a path; it must not create the file.");
    }

    /// <summary>D-09</summary>
    [TestMethod]
    public void PickFolder_Cancel_ReportsCanceled()
    {
        var dialog = Page.Open("ShowFolderDialog");
        Assert.AreEqual("Select Folder", dialog.Title);

        dialog.Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowFolderDialog was canceled.");
    }

    /// <summary>D-10</summary>
    [TestMethod]
    public void PickFolder_PickOne_ReturnsItsPath()
    {
        var dialog = Page.Open("ShowFolderDialog");
        dialog.SetText(DialogPage.Controls.FolderName, FolderA);
        dialog.Press(DialogPage.Controls.Accept);

        Page.WaitForResult($"ShowFolderDialog Result: 1, folderPath: {FolderA}");
    }

    /// <summary>D-11</summary>
    [TestMethod]
    public void PickMultipleFolders_Cancel_ReportsCanceled()
    {
        var dialog = Page.Open("ShowMultiFolderDialog");
        Assert.AreEqual("Select Folders", dialog.Title);

        dialog.Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowMultiFolderDialog was canceled.");
    }

    /// <summary>D-12</summary>
    /// <remarks>
    /// Unlike multiple files, each folder comes back as a full path and the
    /// count is the number of folders.
    /// </remarks>
    [TestMethod]
    public void PickMultipleFolders_PickTwo_ReturnsFullPaths()
    {
        var dialog = Page.Open("ShowMultiFolderDialog");
        dialog.SetText(DialogPage.Controls.FolderName, $"\"{FolderA}\" \"{FolderB}\"");
        dialog.Press(DialogPage.Controls.Accept);

        var result = Page.WaitForResult("ShowMultiFolderDialog Result: 2");
        StringAssert.Contains(result, $"multiFolderBuffer[0]: {FolderA}\n");
        StringAssert.Contains(result, $"multiFolderBuffer[1]: {FolderB}\n");
    }

    /// <summary>D-13</summary>
    [TestMethod]
    public void Back_ReturnsToTheMenuAndThePageOpensAgain()
    {
        var menu = Page.GoBack();

        _page = menu.OpenDialogSample();
        var dialog = Page.Open("ShowAlertDialog");
        dialog.Press(DialogPage.Controls.Accept);
        Page.WaitForResult("ShowAlertDialog Result: 1");
    }

    /// <summary>D-14</summary>
    /// <remarks>
    /// Picking a file that exists raises the overwrite confirmation, because
    /// the sample leaves SaveFileRequest::overwritePrompt at its default.
    /// </remarks>
    [TestMethod]
    public void SaveFile_ExistingFile_AsksBeforeOverwriting()
    {
        var dialog = Page.Open("ShowSaveFileDialog");
        dialog.SetText(DialogPage.Controls.SaveFileName, FileA);
        dialog.Press(DialogPage.Controls.Accept);

        dialog.WaitForNextDialog().Press(DialogPage.Controls.ConfirmYes);

        Page.WaitForResult($"ShowSaveFileDialog Result: 1, savePath: {FileA}");
    }
}
