using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Clipboard;

/// <summary>
/// Covers the "Interoperability" rows (8.1) of the Windows clipboard sample app
/// plan: what another program reads back, and what the app reads from another
/// program. The test process plays the other program (see
/// <see cref="IExternalClipboard"/>).
/// </summary>
[TestClass]
[TestCategory("Clipboard")]
public sealed class ClipboardInteropTests
{
    private const string SampleText = "Hello from native-toolkit";
    private const string SampleHtmlFragment = "<b>Hello</b> from native-toolkit";

    // Short on purpose: PasteFiles shows the first 160 characters of the JSON.
    private static readonly string Work = Path.Combine(Path.GetTempPath(), "ntkcb");
    private static readonly string FileA = Path.Combine(Work, "a.txt");
    private static readonly string FileB = Path.Combine(Work, "b.txt");

    private IUiSession? _session;
    private ClipboardPage? _page;

    [ClassInitialize]
    public static void CreateTestFiles(TestContext _)
    {
        Directory.CreateDirectory(Work);
        File.WriteAllText(FileA, "a");
        File.WriteAllText(FileB, "b");
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
        _page = new MainMenuPage(_session).OpenClipboardSample().Initialize();
    }

    [TestCleanup]
    public void Teardown()
    {
        _session?.Dispose();
        _session = null;
        _page = null;
    }

    private ClipboardPage Page => _page ?? throw new InvalidOperationException("Setup did not run.");

    private IExternalClipboard Other =>
        (_session ?? throw new InvalidOperationException("Setup did not run.")).ExternalClipboard;

    /// <summary>CopyPlainText -> Notepad</summary>
    [TestMethod]
    public void CopyPlainText_AnotherProgramReadsTheSameText()
    {
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);

        Assert.AreEqual(SampleText, Other.ReadText());
    }

    /// <summary>CopyHtml -> Word / browser (bold kept) and Notepad (fallback text)</summary>
    [TestMethod]
    public void CopyHtml_AnotherProgramReadsBoldHtmlAndAPlainFallback()
    {
        Page.PressAndExpect("CopyHtml", "CopyHtml", 0);

        var html = Other.ReadHtml() ?? throw new AssertFailedException("No HTML Format on the clipboard.");
        StringAssert.StartsWith(html, "Version:", "CF_HTML must start with its header.");
        StringAssert.Contains(html, SampleHtmlFragment);
        Assert.AreEqual(SampleText, Other.ReadText());
    }

    /// <summary>CopyFiles -> Explorer</summary>
    [TestMethod]
    public void CopyFiles_AnotherProgramReadsBothFiles()
    {
        Page.PressAndExpect("CopyFiles", "CopyFiles", 0);

        var files = Other.ReadFiles() ?? throw new AssertFailedException("No CF_HDROP on the clipboard.");
        Assert.HasCount(2, files);
        StringAssert.EndsWith(files[0], "native-toolkit-clipboard-sample-1.txt");
        StringAssert.EndsWith(files[1], "native-toolkit-clipboard-sample-2.txt");
        Assert.IsTrue(files.All(File.Exists), "The copied paths must point at existing files.");
    }

    /// <summary>Explorer -> PasteFiles</summary>
    [TestMethod]
    public void FilesFromAnotherProgram_ArePasted()
    {
        Other.WriteFiles(new[] { FileA, FileB });

        var result = Page.PressAndExpect("PasteFiles", "PasteFiles", 0);

        // The result shows the JSON, where backslashes are escaped.
        StringAssert.Contains(result, JsonPath(FileA));
        StringAssert.Contains(result, JsonPath(FileB));
    }

    /// <summary>CopyImage -> Paint</summary>
    [TestMethod]
    public void CopyImage_AnotherProgramReadsAn8x8Dib()
    {
        Page.PressAndExpect("CopyImage", "CopyImage", 0);

        var dib = Other.ReadDib() ?? throw new AssertFailedException("No CF_DIB on the clipboard.");
        Assert.AreEqual(40, BitConverter.ToInt32(dib, 0), "biSize");
        Assert.AreEqual(8, BitConverter.ToInt32(dib, 4), "biWidth");
        Assert.AreEqual(8, BitConverter.ToInt32(dib, 8), "biHeight");
        Assert.AreEqual((ushort)32, BitConverter.ToUInt16(dib, 14), "biBitCount");
    }

    /// <summary>Paint -> PasteImage</summary>
    [TestMethod]
    public void ImageFromAnotherProgram_IsPasted()
    {
        Other.WriteDib(BuildDib(width: 4, height: 2));

        Page.PressAndWaitFor("PasteImage", "width=4, height=2, bitCount=32");
    }

    /// <summary>CopyMultipleFormats -> Word / Notepad (each consumer picks its format)</summary>
    [TestMethod]
    public void CopyMultipleFormats_AnotherProgramSeesBothRichestFirst()
    {
        Page.PressAndExpect("CopyMultipleFormats", "CopyMultipleFormats", 0);

        var formats = Other.FormatNames();
        var html = formats.ToList().IndexOf("HTML Format");
        var text = formats.ToList().IndexOf("CF_UNICODETEXT");
        Assert.IsTrue(html >= 0 && text >= 0, $"Formats on the clipboard: {string.Join(", ", formats)}");
        Assert.IsLessThan(text, html, "The richest format (HTML Format) must be placed before CF_UNICODETEXT.");
        StringAssert.Contains(Other.ReadHtml(), SampleHtmlFragment);
        Assert.AreEqual(SampleText, Other.ReadText());
    }

    /// <summary>text + HTML -> GetPreferredFormat</summary>
    [TestMethod]
    public void PreferredFormat_ForTextAndHtml_IsUnicodeText()
    {
        Page.PressAndExpect("CopyMultipleFormats", "CopyMultipleFormats", 0);

        Page.PressAndWaitFor("GetPreferredFormat", "[GetPreferredFormat] errorCode=0\nCF_UNICODETEXT");
    }

    /// <summary>files only -> GetPreferredFormat</summary>
    [TestMethod]
    public void PreferredFormat_ForFilesOnly_IsHdrop()
    {
        Other.WriteFiles(new[] { FileA });

        Page.PressAndWaitFor("GetPreferredFormat", "[GetPreferredFormat] errorCode=0\nCF_HDROP");
    }

    /// <summary>image only -> GetPreferredFormat</summary>
    [TestMethod]
    public void PreferredFormat_ForAnImageOnly_IsDib()
    {
        Other.WriteDib(BuildDib(width: 4, height: 2));

        Page.PressAndWaitFor("GetPreferredFormat", "[GetPreferredFormat] errorCode=0\nCF_DIB");
    }

    /// <summary>custom only -> GetPreferredFormat</summary>
    [TestMethod]
    public void PreferredFormat_ForACustomFormatOnly_HasNoCandidate()
    {
        Page.PressAndExpect("CopyCustomFormat", "CopyCustomFormat", 0);

        Page.PressAndWaitFor("GetPreferredFormat", "(no candidate format)");
    }

    private static string JsonPath(string path) => path.Replace("\\", "\\\\");

    /// <summary>A bottom-up 32 bpp BI_RGB DIB of the given size.</summary>
    private static byte[] BuildDib(int width, int height)
    {
        var pixels = width * height * 4;
        var dib = new byte[40 + pixels];
        BitConverter.GetBytes(40).CopyTo(dib, 0);                // biSize
        BitConverter.GetBytes(width).CopyTo(dib, 4);             // biWidth
        BitConverter.GetBytes(height).CopyTo(dib, 8);            // biHeight
        BitConverter.GetBytes((ushort)1).CopyTo(dib, 12);        // biPlanes
        BitConverter.GetBytes((ushort)32).CopyTo(dib, 14);       // biBitCount
        BitConverter.GetBytes(pixels).CopyTo(dib, 20);           // biSizeImage
        for (var i = 40; i < dib.Length; i += 4)
        {
            dib[i + 3] = 0xFF;
        }
        return dib;
    }
}
