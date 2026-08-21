namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Creates a session for the sample app.
/// </summary>
/// <remarks>
/// Tests go through this rather than naming a concrete implementation, so
/// swapping FlaUI for a raw UI Automation client stays inside Infra.
/// </remarks>
public static class UiSessionFactory
{
    public static IUiSession Launch() => FlaUiSession.Launch();
}
