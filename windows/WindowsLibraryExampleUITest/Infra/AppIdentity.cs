using System.Diagnostics;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Resolves the AUMID of the packaged sample app.
/// </summary>
/// <remarks>
/// The package family name carries a publisher hash that is only known once the
/// package is registered on the machine, so it cannot be hard coded. A missing
/// package is reported as a deployment problem rather than surfacing later as an
/// unexplained launch failure.
/// </remarks>
public static class AppIdentity
{
    /// <summary>Identity/@Name from Package.appxmanifest.</summary>
    public const string PackageName = "52870e33-d98c-4b7c-be95-bf290f9eff7b";

    /// <summary>Application/@Id from Package.appxmanifest.</summary>
    public const string ApplicationId = "App";

    public static string ResolveAumid()
    {
        var familyName = QueryPackageFamilyName();
        if (string.IsNullOrWhiteSpace(familyName))
        {
            throw new InvalidOperationException(
                $"The sample app package '{PackageName}' is not registered on this machine. " +
                "Build and deploy WindowsLibraryExample (Visual Studio: Deploy, or " +
                "Add-AppxPackage -Register on the AppX layout) before running the UI tests.");
        }

        return $"{familyName}!{ApplicationId}";
    }

    private static string QueryPackageFamilyName()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add($"(Get-AppxPackage -Name '{PackageName}').PackageFamilyName");

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Could not start powershell.exe to query the package.");

        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit(milliseconds: 30_000);
        return output.Trim();
    }
}
