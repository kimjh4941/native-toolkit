// macOS C ABI 1a-9 probe: the C# declarations for the Unity check (Mono, and IL2CPP if available).
// Not the product binding: names, arguments and error numbers are the probe's. Put it anywhere under
// Assets/. Everything is inside #if UNITY_STANDALONE_OSX && !UNITY_EDITOR (the editor must not try
// __Internal); put the scene's scripts that call it inside the same #if.
//
// Rules (Common.h): every function may be called from any thread and never waits for main. An accepted
// request completes exactly once on the main thread, never synchronously inside the function that
// started it, then its release is called once on main. Called from main, the completion comes after
// the return; called from another thread, it may run in parallel with the caller's code after the call. A rejected one (non-zero return) gets no completion, and its
// release is called before the function returns. Strings received (IntPtr of ntk_string*) are owned:
// free them (Take). Callbacks are static methods with [MonoPInvokeCallback], kept in static fields, and
// catch everything.
//
// Logging is safe from any thread: Log() takes no Unity API. It stamps the line with a Stopwatch time,
// the last frame number Tick() saw and the thread, appends it to the file (LogFile) under a lock, and
// queues it for the screen; Pump() (main, from Update) hands queued lines to Sink.
#if UNITY_STANDALONE_OSX && !UNITY_EDITOR
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using AOT;
using UnityEngine;
using Debug = UnityEngine.Debug;

public static class NtkProbeMac
{
    const string Lib = "__Internal";

    // ---- logging (any thread) ----

    /// Main only: shows a line on the screen (the scene's choice). Called from Pump.
    public static Action<string> Sink = _ => { };
    /// Set once on main in Awake, e.g. Path.Combine(Application.persistentDataPath, "ntk-1a9.log").
    /// Under the sandbox this is inside ~/Library/Containers/<bundle id>/Data/. Delete it after copying the results.
    public static string LogFile;

    static readonly Stopwatch clock = Stopwatch.StartNew();
    static readonly ConcurrentQueue<string> pending = new ConcurrentQueue<string>();
    static readonly ConcurrentQueue<string> pendingExceptions = new ConcurrentQueue<string>();
    static readonly object fileLock = new object();
    static int mainThreadId;
    static volatile int lastFrame = -1;

    /// Main, once from Awake.
    public static void RememberMainThread() => mainThreadId = Thread.CurrentThread.ManagedThreadId;

    /// Main, every Update (also while you want lines on the screen): copies the frame number for Log and
    /// hands the queued lines to Sink.
    public static void Pump()
    {
        lastFrame = Time.frameCount;
        while (pending.TryDequeue(out string line))
        {
            try { Sink(line); } catch (Exception e) { Debug.LogException(e); }
        }
        while (pendingExceptions.TryDequeue(out string text)) Debug.LogError(text);
    }

    /// Any thread: records an exception without touching Unity (Debug.LogError runs in Pump, on main).
    /// The message and the stack trace go through the probe's path redaction first (an IOException can
    /// carry a path with the home folder), so the raw exception object is never logged.
    public static void LogException(Exception e)
    {
        string text = $"exception {e.GetType().Name}: {Redact(e.Message)}";
        Log(text);
        pendingExceptions.Enqueue($"[NTK-1A9] {text}\n{Redact(e.StackTrace ?? "")}");
    }

    static readonly System.Text.RegularExpressions.Regex absolutePath =
        new System.Text.RegularExpressions.Regex(@"/[^\s'""():]+");

    /// Replaces every absolute path in the text with the probe's redacted form (ntk_probe_redact_path).
    public static string Redact(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        return absolutePath.Replace(text, m =>
        {
            try { return Take(ntk_probe_redact_path(Utf8(m.Value))) ?? "..."; }
            catch { return "..."; }
        });
    }

    public static string Where() =>
        $"ms={clock.ElapsedMilliseconds} last-frame={lastFrame} managed-main={(Thread.CurrentThread.ManagedThreadId == mainThreadId ? 1 : 0)}";

    public static void Log(string text)
    {
        string line = $"[NTK-1A9] {text} {Where()}";
        if (LogFile != null)
        {
            try { lock (fileLock) File.AppendAllText(LogFile, line + "\n"); } catch { }
        }
        pending.Enqueue(line);
        if (Thread.CurrentThread.ManagedThreadId == mainThreadId)
        {
            Debug.Log(line);   // Debug.Log does not reach Player.log while PreBuildProcessor turns usePlayerLog off: the file is the record
        }
    }

    // ---- "after return" marks: BeginCall(tag) right before the call, MarkReturned(tag) right after ----
    // A callback line shows after-return=1 when it came after MarkReturned, 0 when it came between
    // BeginCall and MarkReturned (inside the call, for a call made on main), n/a for a tag never begun.
    // Use a tag once per process, or BeginCall again before reusing it; never two calls in flight with
    // the same tag.

    static readonly int[] returned = NewMarks();
    static int[] NewMarks() { var marks = new int[256]; for (int i = 0; i < marks.Length; i++) marks[i] = -1; return marks; }

    public static void BeginCall(IntPtr tag) => Volatile.Write(ref returned[Slot(tag)], 0);
    public static void MarkReturned(IntPtr tag) => Volatile.Write(ref returned[Slot(tag)], 1);
    static int Slot(IntPtr tag) => (int)(tag.ToInt64() & 0xFF);
    static string AfterReturn(IntPtr tag)
    {
        int mark = Volatile.Read(ref returned[Slot(tag)]);
        return mark < 0 ? "after-return=n/a" : $"after-return={mark}";
    }

    // ---- callback types ----
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ReleaseFn(IntPtr userData);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void EchoFn(IntPtr userData, int value, int isMain);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void DialogDoneFn(IntPtr userData, ulong requestId, int error, int button);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ShareDoneFn(IntPtr userData, int error, int chosen, IntPtr serviceTitle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void NotificationEventFn(IntPtr userData, int kind, IntPtr identifier, IntPtr action, IntPtr userText, int isLaunchResponse);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void NotificationDoneFn(IntPtr userData, int error, int granted);

    // ---- Common.h ----
    [DllImport(Lib)] public static extern uint ntk_version();
    [DllImport(Lib)] public static extern IntPtr ntk_string_data(IntPtr s);
    [DllImport(Lib)] public static extern UIntPtr ntk_string_size(IntPtr s);
    [DllImport(Lib)] public static extern void ntk_string_free(IntPtr s);

    // ---- Probe.h ----
    [DllImport(Lib)] public static extern int ntk_probe_thread_info(out int isMain, out ulong threadId, out int hasNSApp);
    [DllImport(Lib)] public static extern int ntk_probe_echo_async(int value, uint delayMs, EchoFn callback, IntPtr userData, ReleaseFn release);
    [DllImport(Lib)] public static extern IntPtr ntk_probe_describe();
    [DllImport(Lib)] public static extern IntPtr ntk_probe_redact_path(byte[] path);

    // ---- Dialog.h (errors: 0 NONE, 1 INVALID_PARAMETER, 6 CANCELED (auto close), 10 SHOW_FAILED; button 0 / 1 / -1) ----
    [DllImport(Lib)] public static extern int ntk_dialog_show_alert_async(byte[] title, byte[] message, byte[] positiveText, byte[] negativeText,
                                                                         uint autoCloseMs, DialogDoneFn callback, IntPtr userData,
                                                                         ReleaseFn release, out ulong requestId);
    /// The control of M-8: the same alert entered the A way (inside a main-queue block).
    [DllImport(Lib)] public static extern int ntk_probe_dialog_show_alert_gcd_async(byte[] title, byte[] message, byte[] positiveText, byte[] negativeText,
                                                                                   uint autoCloseMs, DialogDoneFn callback, IntPtr userData,
                                                                                   ReleaseFn release, out ulong requestId);

    // ---- Share.h (errors: 0 NONE, 1 INVALID_PARAMETER, 6 NOT_FOREGROUND, 7 EMPTY_CONTENT). Never choose a service. ----
    [DllImport(Lib)] public static extern int ntk_share_show_async(byte[] text, uint autoCloseMs, ShareDoneFn callback, IntPtr userData, ReleaseFn release);

    // ---- Notification.h / ProbeNotification.h (errors: 0 NONE, 1 INVALID_PARAMETER, 2 NOT_INITIALIZED,
    //      3 NOT_SUPPORTED, 4 UNKNOWN, 10 PERMISSION_DENIED, 16 WRONG_THREAD) ----
    [DllImport(Lib)] public static extern int ntk_notification_install();
    [DllImport(Lib)] public static extern int ntk_probe_notification_add_listener(NotificationEventFn callback, IntPtr userData, ReleaseFn release, out IntPtr listener);
    [DllImport(Lib)] public static extern void ntk_probe_notification_listener_remove(IntPtr listener);
    [DllImport(Lib)] public static extern int ntk_probe_notification_get_launch_response(out IntPtr identifier, out IntPtr action);
    /// granted carries the status: 0 notDetermined, 1 denied, 2 authorized, 3 provisional.
    [DllImport(Lib)] public static extern int ntk_probe_notification_get_authorization_status(NotificationDoneFn callback, IntPtr userData, ReleaseFn release);
    [DllImport(Lib)] public static extern int ntk_probe_notification_request_permission(NotificationDoneFn callback, IntPtr userData, ReleaseFn release);
    [DllImport(Lib)] public static extern int ntk_probe_notification_schedule_marked(uint seconds, byte[] identifier, byte[] title,
                                                                                     NotificationDoneFn callback, IntPtr userData, ReleaseFn release);
    [DllImport(Lib)] public static extern IntPtr ntk_probe_notification_describe();

    /// NUL-terminated UTF-8; null stays NULL.
    public static byte[] Utf8(string s) => s == null ? null : Encoding.UTF8.GetBytes(s + "\0");

    /// Reads and frees an owned ntk_string*. (The library already writes paths from "<name>.app/" on, or with ~.)
    public static string Take(IntPtr handle)
    {
        if (handle == IntPtr.Zero) return null;
        try
        {
            int size = (int)ntk_string_size(handle).ToUInt64();
            var bytes = new byte[size];
            Marshal.Copy(ntk_string_data(handle), bytes, 0, size);
            return Encoding.UTF8.GetString(bytes);
        }
        finally { ntk_string_free(handle); }
    }

    // The delegates live in static fields so that they are never collected (and IL2CPP keeps them).
    public static readonly ReleaseFn Release = OnRelease;
    public static readonly EchoFn Echo = OnEcho;
    public static readonly DialogDoneFn DialogDone = OnDialogDone;
    public static readonly ShareDoneFn ShareDone = OnShareDone;
    public static readonly NotificationEventFn NotificationEvent = OnNotificationEvent;
    public static readonly NotificationDoneFn NotificationDone = OnNotificationDone;

    [MonoPInvokeCallback(typeof(ReleaseFn))]
    static void OnRelease(IntPtr userData)
    {
        try { Log($"release tag={userData.ToInt64()} {AfterReturn(userData)}"); }
        catch (Exception e) { LogException(e); }
    }

    [MonoPInvokeCallback(typeof(EchoFn))]
    static void OnEcho(IntPtr userData, int value, int isMain)
    {
        try { Log($"echo tag={userData.ToInt64()} value={value} called-on-main={isMain} {AfterReturn(userData)}"); }
        catch (Exception e) { LogException(e); }
    }

    [MonoPInvokeCallback(typeof(DialogDoneFn))]
    static void OnDialogDone(IntPtr userData, ulong requestId, int error, int button)
    {
        try { Log($"dialog tag={userData.ToInt64()} id={requestId} error={error} button={button} {AfterReturn(userData)}"); }
        catch (Exception e) { LogException(e); }
    }

    [MonoPInvokeCallback(typeof(ShareDoneFn))]
    static void OnShareDone(IntPtr userData, int error, int chosen, IntPtr serviceTitle)
    {
        try
        {
            string title = Take(serviceTitle);   // the check never chooses a service
            Log($"share tag={userData.ToInt64()} error={error} chosen={chosen} service={(title ?? "null")} {AfterReturn(userData)}");
        }
        catch (Exception e) { LogException(e); }
    }

    [MonoPInvokeCallback(typeof(NotificationEventFn))]
    static void OnNotificationEvent(IntPtr userData, int kind, IntPtr identifier, IntPtr action, IntPtr userText, int isLaunchResponse)
    {
        try
        {
            Log($"event kind={kind} id={Take(identifier) ?? "null"} action={Take(action) ?? "null"} " +
                $"text-length={(Take(userText)?.Length ?? -1)} launch={isLaunchResponse} listener-tag={userData.ToInt64()}");
        }
        catch (Exception e) { LogException(e); }
    }

    [MonoPInvokeCallback(typeof(NotificationDoneFn))]
    static void OnNotificationDone(IntPtr userData, int error, int granted)
    {
        try { Log($"notification-done tag={userData.ToInt64()} error={error} granted-or-status={granted} {AfterReturn(userData)}"); }
        catch (Exception e) { LogException(e); }
    }

    /// thread_info and where the caller is (M-3). Safe from a worker thread (no Unity API).
    public static void LogThread(string from)
    {
        try
        {
            ntk_probe_thread_info(out int isMain, out ulong tid, out int hasApp);
            Log($"thread from={from} pthread-main={isMain} tid={tid} nsapp={hasApp}");
        }
        catch (Exception e) { Log($"thread from={from} exception={e.GetType().Name}"); }
    }
}
#endif
