using System.Runtime.InteropServices;
using System.Text;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>
/// Win32 declarations used by the Infra layer.
/// </summary>
internal static class Native
{
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hwnd);

    /// <summary>Changes every time the clipboard content changes.</summary>
    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();

    /// <summary>
    /// Returns the first visible top-level window of the process with the given
    /// window class, or <see cref="IntPtr.Zero"/>.
    /// </summary>
    public static IntPtr FindVisibleWindow(int processId, string className)
    {
        var found = IntPtr.Zero;
        EnumWindows((hwnd, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid != processId || !IsWindowVisible(hwnd))
            {
                return true;
            }

            var name = new StringBuilder(256);
            GetClassName(hwnd, name, name.Capacity);
            if (name.ToString() != className)
            {
                return true;
            }

            found = hwnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>True while the window handle still refers to a visible window.</summary>
    public static bool IsVisibleWindow(IntPtr hwnd) => IsWindow(hwnd) && IsWindowVisible(hwnd);
}
