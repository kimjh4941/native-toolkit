using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Dialog;

/// <summary>
/// Covers the dialog sample page: each of the six dialogs, accepted and
/// cancelled, plus returning to the menu (D-01 to D-13 in
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
        if (Directory.Exists(Work))
        {
            Directory.Delete(Work, recursive: true);
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
        Page.Open("ShowFileDialog").Press(DialogPage.Controls.Cancel);

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
        Page.Open("ShowMultiFileDialog").Press(DialogPage.Controls.Cancel);

        Page.WaitForResult("ShowMultiFileDialog was canceled.");
    }

    /// <summary>D-06</summary>
    /// <remarks>
    /// The result is the folder followed by the bare file names, and the count
    /// includes the folder: two files report 3. This pins the current format;
    /// whether to keep it is decided in the C++ API design (stage 3).
    /// </remarks>
    [TestMethod]
    public void OpenMultipleFiles_PickTwo_ReturnsFolderThenNames()
    {
        var dialog = Page.Open("ShowMultiFileDialog");
        dialog.SetText(DialogPage.Controls.OpenFileName, $"\"{FileA}\" \"{FileB}\"");
        dialog.Press(DialogPage.Controls.Accept);

        var result = Page.WaitForResult("ShowMultiFileDialog Result: 3");
        StringAssert.Contains(result, $"multiBuffer[0]: {Work}\n");
        StringAssert.Contains(result, "multiBuffer[1]: a.txt\n");
        StringAssert.Contains(result, "multiBuffer[2]: b.txt\n");
    }

    /// <summary>D-07</summary>
    [TestMethod]
    public void SaveFile_Cancel_ReportsCanceled()
    {
        Page.Open("ShowSaveFileDialog").Press(DialogPage.Controls.Cancel);

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
}
