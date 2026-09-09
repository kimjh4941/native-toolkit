using WindowsLibraryExampleUITest.Infra;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Verifies the pieces every other UI test depends on: the package is deployed,
/// the app launches from its AUMID, and automation elements are reachable.
/// </summary>
[TestClass]
public sealed class SmokeTests
{
    [TestMethod]
    public void Aumid_ResolvesFromTheRegisteredPackage()
    {
        var aumid = AppIdentity.ResolveAumid();

        StringAssert.EndsWith(aumid, $"!{AppIdentity.ApplicationId}");
        StringAssert.StartsWith(aumid, AppIdentity.PackageName);
    }

    [TestMethod]
    public void App_LaunchesAndShowsTheMainMenu()
    {
        using var session = UiSessionFactory.Launch();

        // The Clipboard card is the entry point for every clipboard test.
        var found = session.TryWaitForElement("ClipboardCard", TimeSpan.FromSeconds(10), out var card);

        Assert.IsTrue(
            found,
            "The main menu did not expose a 'ClipboardCard' element. The deployed package may " +
            "predate the Clipboard sample page, or the element may lack an AutomationId.");
        Assert.IsNotNull(card);
    }
}
