namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// The clipboard as another application sees it.
/// </summary>
/// <remarks>
/// The test process stands in for Notepad, Word, Paint or Explorer. It is a
/// separate process from the sample app, and the clipboard is shared by the
/// whole session, so to the app a read or write from here is the same as one
/// from any other program. What the toolkit is responsible for is the content
/// of each format, which is what these calls check; how another program
/// renders that content is not.
/// Reads return null when the format is not on the clipboard.
/// </remarks>
public interface IExternalClipboard
{
    /// <summary>CF_UNICODETEXT.</summary>
    string? ReadText();

    void WriteText(string text);

    /// <summary>The registered "HTML Format" (CF_HTML: a header and the fragment), decoded from UTF-8.</summary>
    string? ReadHtml();

    /// <summary>CF_HDROP: the full paths of the files.</summary>
    IReadOnlyList<string>? ReadFiles();

    void WriteFiles(IEnumerable<string> paths);

    /// <summary>CF_DIB: a BITMAPINFOHEADER followed by the pixels.</summary>
    byte[]? ReadDib();

    void WriteDib(byte[] dib);

    /// <summary>
    /// The formats on the clipboard, by name: "CF_UNICODETEXT" style names for
    /// the standard ones, the registered name for the others.
    /// </summary>
    IReadOnlyList<string> FormatNames();

    /// <summary>Empties the clipboard.</summary>
    void Clear();
}
