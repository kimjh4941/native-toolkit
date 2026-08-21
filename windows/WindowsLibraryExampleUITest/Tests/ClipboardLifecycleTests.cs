using WindowsLibraryExampleUITest.Infra;
using WindowsLibraryExampleUITest.Pages;

namespace WindowsLibraryExampleUITest.Tests;

/// <summary>
/// Covers the manager lifecycle rows of the sample app plan: the three-state
/// model, the shutdown gate, and the owner-thread restriction.
/// </summary>
/// <remarks>
/// The sample tracks Uninitialized / Ready / ShuttingDown for the lifetime of
/// the process, so each test starts a fresh instance. Several of these cases
/// deliberately drive the app into ShuttingDown and leave it there.
/// </remarks>
[TestClass]
public sealed class ClipboardLifecycleTests
{
    private const int NotInitialized = 2;
    private const int Canceled = 15;
    private const int WrongThread = 14;

    private const string ShuttingDownGuard = "Shutting down. Press CanDestroy, then Uninitialize again.";
    private const string StateReady = "manager state: Ready";
    private const string StateShuttingDown = "manager state: Shutting down";
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

    /// <summary>Drives the app into ShuttingDown deterministically.</summary>
    /// <remarks>
    /// The request is only posted to the dispatch window, so it is still queued
    /// when the same handler calls uninit. Splitting this across two presses would
    /// let the message pump complete the request first and the drain path would
    /// never be exercised.
    /// </remarks>
    private void EnterShuttingDown()
    {
        Page.Initialize();
        Page.Press("RequestAndImmediateUninitialize");

        // Read this from the log, not the result line: the pending request is
        // cancelled by the drain moments later and its callback overwrites the
        // result line before a poll can observe the uninit outcome.
        var log = Page.WaitForLog("then uninit returned FALSE");
        StringAssert.Contains(log, $"errorCode={Canceled}");

        // Wait for the cancelled callback to land as well, so a later press is
        // not overwritten by it mid-assertion.
        Page.WaitForLog($"[Request] completed id=");
        Page.WaitForLog($"error={Canceled}");

        Page.WaitFor(StateShuttingDown);
    }

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

    [TestMethod]
    public void RequestThenImmediateUninitialize_ReportsCanceledAndEntersShuttingDown()
    {
        EnterShuttingDown();
    }

    [TestMethod]
    public void ShuttingDown_RefusesNormalOperations()
    {
        EnterShuttingDown();

        // The guard runs before the bridge call, so no errorCode is reported at all.
        var result = Page.PressAndWaitFor("CopyPlainText", ShuttingDownGuard);

        StringAssert.Contains(result, StateShuttingDown);
    }

    [TestMethod]
    public void ShuttingDown_RefusesInitialize()
    {
        EnterShuttingDown();

        // A fresh Init would report success without reopening the gate, so the
        // sample refuses it rather than showing a misleading result.
        var result = Page.PressAndWaitFor("InitializeManager", ShuttingDownGuard);

        StringAssert.Contains(result, StateShuttingDown);
    }

    [TestMethod]
    public void ForceInitialize_WhileShuttingDown_DoesNotReopenTheGate()
    {
        EnterShuttingDown();

        Page.PressAndExpect("ErrForceInitialize", "Force Initialize while shutting down", 0);

        // Init reported success, yet the lifecycle gate is still closed.
        var afterCopy = Page.PressAndExpect(
            "ErrCopyAfterUninitialize", "CopyPlainText (after Uninitialize)", NotInitialized);

        StringAssert.Contains(afterCopy, StateShuttingDown);
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
