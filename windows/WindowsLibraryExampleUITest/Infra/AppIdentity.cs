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
    private static readonly TimeSpan QueryTimeout = TimeSpan.FromSeconds(30);

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
        // Select a single value: more than one registration for the same identity
        // would otherwise produce a multi-line result that is not an AUMID.
        startInfo.ArgumentList.Add(
            $"Get-AppxPackage -Name '{PackageName}' | Select-Object -First 1 -ExpandProperty PackageFamilyName");

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Could not start powershell.exe to query the package.");

        // Read asynchronously: reading to the end first would block past the
        // timeout if PowerShell stalls, which is exactly the case the timeout
        // exists for.
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit((int)QueryTimeout.TotalMilliseconds))
        {
            TryKill(process);
            throw new InvalidOperationException(
                $"Querying the package family name timed out after {QueryTimeout.TotalSeconds:0} seconds. " +
                "The UI tests cannot resolve the AUMID without it.");
        }

        var output = stdout.GetAwaiter().GetResult().Trim();
        var error = stderr.GetAwaiter().GetResult().Trim();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"Querying the package family name failed with exit code {process.ExitCode}. {error}");
        }

        return output;
    }

    private static void TryKill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch
        {
            // Already gone, or not killable; the timeout is reported either way.
        }
    }
}
