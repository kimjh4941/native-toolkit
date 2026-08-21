using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the rows that depend on state living outside a single page: the
/// process-wide busy flag, page re-entry, and completing a pending shutdown.
/// </summary>
[TestClass]
public sealed class ClipboardBusyAndNavigationTests
{
    private const int Canceled = 15;

    private const string BusyGuard = "Busy: another clipboard operation is running";
    private const string StateReady = "manager state: Ready";
    private const string StateShuttingDown = "manager state: Shutting down";
    private const string StateUninitialized = "manager state: Uninitialized";
    private const string ReserveToken = "[Reserve] OK";

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

    /// <summary>Starts the deliberately slow read-only worker (5 s).</summary>
    /// <remarks>
    /// A normal copy finishes in milliseconds, so busy behaviour could otherwise
    /// only be observed by racing the test against the app.
    /// </remarks>
    private void StartDelayedWorker() => Page.Initialize().Press("DelayedWorkerCheck");

    // ---- Busy ----------------------------------------------------------

    [TestMethod]
    public void Busy_RefusesAnotherClipboardOperation()
    {
        StartDelayedWorker();

        var result = Page.PressAndWaitFor("CopyPlainText", BusyGuard);

        // The guard runs before the bridge call, so no errorCode is reported.
        StringAssert.Contains(result, StateReady);
    }

    [TestMethod]
    public void Busy_StillAllowsCanDestroy()
    {
        StartDelayedWorker();

        // CanDestroy is the one operation allowed while busy, so the lifecycle
        // race stays observable. The manager is initialized and the gate is open,
        // so it reports that destruction is not yet possible.
        var result = Page.PressAndExpect("CanDestroy", "CanDestroy", 0);

        StringAssert.Contains(result, "returned FALSE");
    }

    [TestMethod]
    public void Busy_SurvivesLeavingAndReenteringThePage()
    {
        StartDelayedWorker();

        _page = Page.GoBack().OpenClipboardSample();

        // The busy flag lives outside the page, so a fresh page instance must not
        // let a second clipboard operation start.
        Page.PressAndWaitFor("CopyPlainText", BusyGuard);
    }

    [TestMethod]
    public void Busy_IsReleasedWhenTheWorkerFinishes()
    {
        StartDelayedWorker();

        Page.WaitFor(ClipboardPage.ResultMarker("Delayed Worker Check", 0));

        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);
    }

    // ---- Page re-entry -------------------------------------------------

    [TestMethod]
    public void PageReentry_KeepsManagerStateAndClearsTheLog()
    {
        Page.Initialize();

        // Reserving writes a log line and completes synchronously, so the log is
        // guaranteed to hold content before leaving the page. Not every operation
        // logs: a plain copy only updates the result line.
        Page.PressAndExpect("ReserveDeferredFormats", "ReserveDeferredFormats", 0);
        Page.WaitForLog(ReserveToken);

        _page = Page.GoBack().OpenClipboardSample();

        // The manager outlives the page, but the log is a page member.
        StringAssert.Contains(Page.ResultText, StateReady);

        // Assert on the token written before leaving, not on the log being empty.
        // The reservation stays active for the lifetime of the process, so render
        // requests keep arriving and are legitimately logged by the new page.
        Assert.IsFalse(
            Page.LogText.Contains(ReserveToken, StringComparison.Ordinal),
            "The previous page log survived re-entry.");

        // Still usable without initializing again.
        Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);
    }

    [TestMethod]
    public void PageReentry_DoesNotRestoreStateOwnedByThePreviousPage()
    {
        Page.Initialize().Press("GetClipboardHistory");

        // Confirm the request was accepted before leaving, so there really is a
        // completion in flight.
        Page.WaitForLog("[Request] accepted id=");

        _page = Page.GoBack().OpenClipboardSample();

        // The captured history id belonged to the previous page instance and is
        // deliberately not restored, so the follow-up action has to be re-run.
        Page.PressAndWaitFor("RestoreHistoryItem", "No captured id. Press GetClipboardHistory first.");

        // The previous page's request bookkeeping is gone too. Note that the exact
        // moment the completion is delivered is not observable from outside the
        // app, so this asserts the contract that survives either timing: nothing
        // from the previous page instance is restored.
        Assert.IsFalse(
            Page.LogText.Contains("[Request] accepted id=", StringComparison.Ordinal),
            "The previous page request log survived re-entry.");
    }

    // ---- Completing a pending shutdown ---------------------------------

    [TestMethod]
    public void PendingShutdown_AfterDrain_ReportsDestroyable()
    {
        EnterShuttingDown();

        var result = Page.PressAndExpect("CanDestroy", "CanDestroy", 0);

        StringAssert.Contains(result, "returned TRUE");
    }

    [TestMethod]
    public void PendingShutdown_SecondUninitialize_CompletesTeardown()
    {
        EnterShuttingDown();
        Page.PressAndExpect("CanDestroy", "CanDestroy", 0);

        var result = Page.PressAndExpect("Uninitialize", "Uninitialize", 0);

        StringAssert.Contains(result, "temp cleanup pending");
        StringAssert.Contains(result, StateUninitialized);
    }

    [TestMethod]
    public void Uninitialize_RunsTempCleanupAndLogsTheOutcome()
    {
        Page.Initialize();

        // CopyFiles writes the temp files that the cleanup then removes.
        Page.PressAndExpect("CopyFiles", "CopyFiles", 0);
        Page.Uninitialize();

        // Cleanup runs as a separate worker, so its outcome reaches the log
        // rather than replacing the uninitialize result.
        var log = Page.WaitForLog("[Cleanup] temp cleanup");
        StringAssert.Contains(log, "[Cleanup] temp cleanup succeeded");
    }

    [TestMethod]
    public void Reinitialize_AfterFullTeardown_WorksAgain()
    {
        Page.Initialize();
        Page.PressAndExpect("CopyFiles", "CopyFiles", 0);
        Page.Uninitialize();

        // Wait for the cleanup worker: while it holds the busy flag the UI-direct
        // initialize would be refused.
        Page.WaitForLog("[Cleanup] temp cleanup");

        Page.PressAndExpect("InitializeManager", "InitializeManager", 0);
        var result = Page.PressAndExpect("CopyPlainText", "CopyPlainText", 0);

        StringAssert.Contains(result, StateReady);
    }

    private void EnterShuttingDown()
    {
        Page.Initialize();
        Page.Press("RequestAndImmediateUninitialize");

        // Read from the log: the result line is overwritten by the cancelled
        // request's callback before a poll can observe the uninit outcome.
        var log = Page.WaitForLog("then uninit returned FALSE");
        StringAssert.Contains(log, $"errorCode={Canceled}");

        Page.WaitForLog("[Request] completed id=");
        Page.WaitForLog($"error={Canceled}");
        Page.WaitFor(StateShuttingDown);
    }
}
