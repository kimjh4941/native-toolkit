using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests.Clipboard;

/// <summary>
/// Covers the manager lifecycle rows of the sample app plan: the three-state
/// model, the shutdown gate, and the owner-thread restriction.
/// </summary>
/// <remarks>
/// The sample tracks Uninitialized / Ready / ShuttingDown for the lifetime of
/// the process, so each test starts a fresh instance. Since stage 5 a close no
/// longer fails for want of a message loop (design E-19), and the sample has no
/// way left to make it fail on demand, so ShuttingDown is not driven here; how
/// Close fails and recovers is covered by the unit tests (C-5 to C-8, CT-22).
/// </remarks>
[TestClass]
[TestCategory("Clipboard")]
public sealed class ClipboardLifecycleTests
{
    private const int Canceled = 15;
    private const int WrongThread = 14;

    private const string StateReady = "manager state: Ready";
    private const string StateUninitialized = "manager state: Uninitialized";

    private IUiSession? _session;
    private ClipboardPage? _page;

    [TestInitialize]
    public void Setup()
    {
        _session = UiSessionFactory.Launch();
        _page = new MainMenuPage(_session).OpenClipboardSample();
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
    public void Initialize_CalledTwice_SucceedsBothTimes()
    {
        Page.Initialize();

        // Move the result line off the initialize marker first. Without this the
        // wait below would be satisfied by the first call's result and would pass
        // even if the second press never reached the bridge.
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);

        // The bridge is called again on purpose: initialization is idempotent from
        // the owner thread and must not be short-circuited by the sample.
        var result = Page.PressAndExpect("InitializeManager", "InitializeManager", 0);

        StringAssert.Contains(result, StateReady);
    }

    [TestMethod]
    public void Uninitialize_WithNothingPending_CompletesAndAllowsDestroy()
    {
        Page.Initialize().Uninitialize();

        var afterUninit = Page.WaitFor(StateUninitialized);
        StringAssert.Contains(afterUninit, "temp cleanup pending");

        var canDestroy = Page.PressAndExpect("CanDestroy", "CanDestroy", 0);
        StringAssert.Contains(canDestroy, "returned TRUE");
    }

    /// <remarks>
    /// The request is only posted to the dispatch window, so it is still queued
    /// when the same handler closes. Close cancels it and delivers the
    /// cancellation itself (stage 5 design E-19), so the uninit succeeds at the
    /// first attempt and the request is answered once, with Canceled. Until
    /// stage 5 this left the app shutting down, waiting for a message loop.
    /// </remarks>
    [TestMethod]
    public void RequestThenImmediateUninitialize_DeliversTheCancellationAndCloses()
    {
        Page.Initialize();
        Page.Press("RequestAndImmediateUninitialize");

        // Read from the log: the cancelled request's completion is queued to
        // the UI and overwrites the result line after the uninit outcome.
        var log = Page.WaitForLog("then uninit returned TRUE");
        StringAssert.Contains(log, "errorCode=0");

        Page.WaitForLog("[Request] completed id=");
        Page.WaitForLog($"error={Canceled}");
        Page.WaitFor(StateUninitialized);
    }

    [TestMethod]
    public void ReserveDeferredFormats_FromWorkerThread_ReportsWrongThread()
    {
        Page.Initialize();

        var result = Page.PressAndExpect(
            "ReserveDeferredOnWorker", "ReserveDeferred (worker thread)", WrongThread);

        StringAssert.Contains(result, StateReady);
    }

    [TestMethod]
    public void Uninitialize_FromWorkerThread_ReportsWrongThreadAndStaysReady()
    {
        Page.Initialize();

        var result = Page.PressAndExpect(
            "UninitializeOnWorker", "Uninitialize (worker thread)", WrongThread);

        // The call never reaches the code that closes the gate, so the state must
        // not move to ShuttingDown.
        StringAssert.Contains(result, StateReady);

        // Still usable afterwards.
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);
    }
}
