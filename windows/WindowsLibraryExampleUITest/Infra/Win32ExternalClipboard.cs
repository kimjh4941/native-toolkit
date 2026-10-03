using System.Runtime.InteropServices;
using System.Text;

namespace WindowsLibraryExampleUITest.Infra;

/// <summary>Win32 implementation of <see cref="IExternalClipboard"/>.</summary>
internal sealed class Win32ExternalClipboard : IExternalClipboard
{
    private const uint CfDib = 8;
    private const uint CfUnicodeText = 13;
    private const uint CfHdrop = 15;
    private static readonly uint CfHtml = RegisterClipboardFormat("HTML Format");

    private static readonly Dictionary<uint, string> StandardNames = new()
    {
        [1] = "CF_TEXT",
        [2] = "CF_BITMAP",
        [7] = "CF_OEMTEXT",
        [8] = "CF_DIB",
        [13] = "CF_UNICODETEXT",
        [15] = "CF_HDROP",
        [16] = "CF_LOCALE",
        [17] = "CF_DIBV5",
    };

    public string? ReadText() => WithClipboard(() =>
    {
        var bytes = ReadFormat(CfUnicodeText);
        return bytes is null ? null : Encoding.Unicode.GetString(bytes).TrimEnd('\0');
    });

    public void WriteText(string text) =>
        Write(CfUnicodeText, Encoding.Unicode.GetBytes(text + "\0"));

    public string? ReadHtml() => WithClipboard(() =>
    {
        var bytes = ReadFormat(CfHtml);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes).TrimEnd('\0');
    });

    public IReadOnlyList<string>? ReadFiles() => WithClipboard<IReadOnlyList<string>?>(() =>
    {
        var drop = GetClipboardData(CfHdrop);
        if (drop == IntPtr.Zero)
        {
            return null;
        }
        var count = DragQueryFile(drop, 0xFFFFFFFF, null, 0);
        var files = new List<string>();
        for (uint i = 0; i < count; i++)
        {
            var length = DragQueryFile(drop, i, null, 0);
            var name = new StringBuilder((int)length + 1);
            DragQueryFile(drop, i, name, (uint)name.Capacity);
            files.Add(name.ToString());
        }
        return files;
    });

    public void WriteFiles(IEnumerable<string> paths)
    {
        // DROPFILES (20 bytes, wide names) followed by a double-null-terminated list.
        var list = Encoding.Unicode.GetBytes(string.Join("\0", paths) + "\0\0");
        var data = new byte[20 + list.Length];
        BitConverter.GetBytes(20).CopyTo(data, 0);   // pFiles
        BitConverter.GetBytes(1).CopyTo(data, 16);   // fWide
        list.CopyTo(data, 20);
        Write(CfHdrop, data);
    }

    public byte[]? ReadDib() => WithClipboard(() => ReadFormat(CfDib));

    public void WriteDib(byte[] dib) => Write(CfDib, dib);

    public IReadOnlyList<string> FormatNames() => WithClipboard<IReadOnlyList<string>>(() =>
    {
        var names = new List<string>();
        uint format = 0;
        while ((format = EnumClipboardFormats(format)) != 0)
        {
            if (StandardNames.TryGetValue(format, out var standard))
            {
                names.Add(standard);
                continue;
            }
            var name = new StringBuilder(256);
            names.Add(GetClipboardFormatName(format, name, name.Capacity) > 0 ? name.ToString() : $"#{format}");
        }
        return names;
    });

    public void Clear() => WithClipboard<object?>(() =>
    {
        Check(EmptyClipboard(), "EmptyClipboard");
        return null;
    });

    private static void Write(uint format, byte[] data) => WithClipboard<object?>(() =>
    {
        Check(EmptyClipboard(), "EmptyClipboard");

        var memory = GlobalAlloc(GmemMoveable, (UIntPtr)data.Length);
        var pointer = GlobalLock(memory);
        Marshal.Copy(data, 0, pointer, data.Length);
        GlobalUnlock(memory);

        // On success the system owns the memory.
        Check(SetClipboardData(format, memory) != IntPtr.Zero, "SetClipboardData");
        return null;
    });

    /// <summary>Copies the data of one format; call with the clipboard open.</summary>
    private static byte[]? ReadFormat(uint format)
    {
        var handle = GetClipboardData(format);
        if (handle == IntPtr.Zero)
        {
            return null;
        }
        var pointer = GlobalLock(handle);
        try
        {
            var bytes = new byte[(int)GlobalSize(handle)];
            Marshal.Copy(pointer, bytes, 0, bytes.Length);
            return bytes;
        }
        finally
        {
            GlobalUnlock(handle);
        }
    }

    /// <summary>
    /// Opens the clipboard with an owner window and runs the body.
    /// </summary>
    /// <remarks>
    /// The owner is a message-only window: with no owner, EmptyClipboard leaves
    /// the clipboard ownerless and SetClipboardData then fails. Another process
    /// (the app, the history service) may hold the clipboard for a moment, so
    /// opening is retried.
    /// </remarks>
    private static T WithClipboard<T>(Func<T> body)
    {
        var owner = CreateWindowEx(0, "STATIC", "ntk-uitest-clipboard", 0, 0, 0, 0, 0,
            HwndMessage, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        try
        {
            var deadline = DateTime.UtcNow + OpenTimeout;
            while (!OpenClipboard(owner))
            {
                if (DateTime.UtcNow > deadline)
                {
                    throw new InvalidOperationException(
                        $"Could not open the clipboard within {OpenTimeout.TotalSeconds:0} seconds.");
                }
                Thread.Sleep(50);
            }
            try
            {
                return body();
            }
            finally
            {
                CloseClipboard();
            }
        }
        finally
        {
            DestroyWindow(owner);
        }
    }

    private static void Check(bool ok, string call)
    {
        if (!ok)
        {
            throw new InvalidOperationException($"{call} failed: Win32 error {Marshal.GetLastWin32Error()}.");
        }
    }

    private static readonly TimeSpan OpenTimeout = TimeSpan.FromSeconds(5);
    private const uint GmemMoveable = 0x0002;
    private static readonly IntPtr HwndMessage = new(-3);

    [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetClipboardData(uint format, IntPtr memory);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint EnumClipboardFormats(uint format);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern int GetClipboardFormatName(uint format, StringBuilder name, int maxCount);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint RegisterClipboardFormat(string name);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint DragQueryFile(IntPtr drop, uint index, StringBuilder? file, uint length);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern UIntPtr GlobalSize(IntPtr memory);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(int exStyle, string className, string windowName, int style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool DestroyWindow(IntPtr hwnd);
}
