using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the Error cases section of the sample app plan: each button drives one
/// bridge call whose expected error code is fixed by the design.
/// </summary>
/// <remarks>
/// Every test launches its own instance. The sample keeps its manager state for
/// the lifetime of the process, and two of these cases deliberately leave that
/// state changed, so sharing one instance would couple the tests to their order.
/// </remarks>
[TestClass]
public sealed class ClipboardErrorCaseTests
{
    private const int InvalidParameter = 1;
    private const int NotInitialized = 2;
    private const int FormatUnavailable = 5;
    private const int BufferTooSmall = 7;

    private IUiSession? _session;
    private ClipboardPage? _page;

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

    [TestMethod]
    public void CopyPlainText_WithNullText_ReportsInvalidParameter()
        => Page.PressAndExpect("ErrCopyPlainTextNull", "CopyPlainText (null)", InvalidParameter);

    [TestMethod]
    public void PastePlainText_AfterClear_ReportsFormatUnavailable()
        // Not EMPTY(4): the toolkit checks format availability before it asks for
        // the data, so an empty clipboard surfaces as FORMAT_UNAVAILABLE(5).
        => Page.PressAndExpect("ErrPasteAfterClear", "PastePlainText (after Clear)", FormatUnavailable);

    [TestMethod]
    public void PasteHtml_WithOnlyPlainTextOnTheClipboard_ReportsFormatUnavailable()
        => Page.PressAndExpect("ErrPasteHtmlTextOnly", "PasteHtml (text only)", FormatUnavailable);

    [TestMethod]
    public void PasteImage_SizeQuery_ReportsBufferTooSmall()
    {
        // An image has to be on the clipboard first: pasteImage checks format
        // availability before it ever computes a size, so without this step the
        // call reports FORMAT_UNAVAILABLE(5) and never exercises the buffer contract.
        Page.PressAndExpect("CopyImage", "CopyImage", 0);

        // First phase of the two-call buffer contract: no buffer, so the toolkit
        // reports BUFFER_TOO_SMALL together with the size the caller must allocate.
        Page.PressAndExpect("ErrPasteImageSizeQuery", "PasteImage (size query only)", BufferTooSmall);
    }

    [TestMethod]
    public void CopyMultipleFormats_WithCfBitmap_ReportsInvalidParameter()
        // CF_BITMAP is rejected outright: there is no HBITMAP ownership path.
        => Page.PressAndExpect("ErrMultiCfBitmap", "CopyMultipleFormats (CF_BITMAP)", InvalidParameter);

    [TestMethod]
    public void CopyMultipleFormats_WithDuplicateFormat_ReportsInvalidParameter()
        => Page.PressAndExpect("ErrMultiDuplicate", "CopyMultipleFormats (duplicate format)", InvalidParameter);

    [TestMethod]
    public void CopyMultipleFormats_WithMismatchedPayloadKind_ReportsInvalidParameter()
        // CF_DIB only accepts a base64 payload.
        => Page.PressAndExpect("ErrMultiTypeMismatch", "CopyMultipleFormats (CF_DIB + text)", InvalidParameter);

    [TestMethod]
    public void CopyFiles_WithEmptyArray_ReportsInvalidParameter()
        => Page.PressAndExpect("ErrCopyFilesEmpty", "CopyFiles (empty array)", InvalidParameter);

    [TestMethod]
    public void CancelClipboardRequest_WithUnknownId_ReportsInvalidParameter()
        => Page.PressAndExpect("ErrCancelUnknownId", "CancelClipboardRequest (unknown id)", InvalidParameter);

    [TestMethod]
    public void CopyPlainText_AfterUninitialize_ReportsNotInitialized()
    {
        Page.Uninitialize();

        Page.PressAndExpect("ErrCopyAfterUninitialize", "CopyPlainText (after Uninitialize)", NotInitialized);
    }
}
