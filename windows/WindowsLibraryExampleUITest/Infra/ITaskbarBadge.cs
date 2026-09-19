namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// The badge on the sample app's taskbar button.
/// </summary>
/// <remarks>
/// A badge is read as text: null when there is no badge, the number for a
/// count badge, and a single icon-font character for a glyph badge (for
/// example U+EDAD for "alert" on Windows 11 build 26200). The glyph character
/// prints as nothing, so failure messages show code points.
/// </remarks>
public interface ITaskbarBadge
{
    /// <summary>
    /// Waits until the badge satisfies the predicate and returns it. Throws with
    /// the last value seen when it does not within the timeout.
    /// </summary>
    string? WaitFor(Func<string?, bool> predicate, TimeSpan? timeout = null);
}
