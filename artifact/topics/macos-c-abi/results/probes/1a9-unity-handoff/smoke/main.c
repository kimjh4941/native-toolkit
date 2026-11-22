// macOS C ABI 1a-9 probe: command-line smoke. A process without an app bundle and without NSApp, so
// nothing here shows an alert, a picker or a notification, and UNUserNotificationCenter is never
// touched (the notification functions must return NOT_SUPPORTED). The dialog and share calls are made
// only while NSApp does not exist, where they complete with SHOW_FAILED / NOT_FOREGROUND without UI.
//
// The contract checked (Common.h, iOS / Android AC-5): a completion comes exactly once, on main, never
// synchronously inside the entry, and then its release; a call made on main therefore sees it after
// the return. A call made on another thread may see it in parallel with its own code after the call,
// so for those only "on main, not on the calling thread, once, release after it" is checked; the
// times are printed as information. All state shared between threads is C11 atomics.
#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <NtkProbeMacCApi/NativeToolkitC/Probe.h>
#include <NtkProbeMacCApi/NativeToolkitC/Dialog.h>
#include <NtkProbeMacCApi/NativeToolkitC/Share.h>
#include <NtkProbeMacCApi/NativeToolkitC/ProbeNotification.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (cond) { printf("ok   "); } else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

/* What the callbacks saw, per tag (user_data). */
typedef struct {
    atomic_int returned;            /* set by the caller after the call returned */
    atomic_int completions, releases;
    atomic_int completion_on_main, completion_after_return;
    atomic_int completion_seq, release_seq;          /* order of the two calls (global counter) */
    atomic_int release_before_return;
    atomic_int release_on_main, in_completion, release_during_completion;
    atomic_ullong completion_thread, release_thread; /* pthread_threadid_np */
    atomic_int error, value;
    _Atomic double t_call, t_ret, t_cb;              /* information only */
} Tag;
static Tag tags[32];
static atomic_int sequence;
static double entry_delay = 0;   /* NTK_PROBE_ENTRY_DELAY_MS: probe-only hook, see run.sh */

static double now(void) { return CFAbsoluteTimeGetCurrent(); }
static uint64_t tid(void) { uint64_t t = 0; pthread_threadid_np(NULL, &t); return t; }
static Tag* tag_of(void* user_data) { return &tags[(intptr_t)user_data]; }

/* Called at the start of every completion and event callback; finish_completion at its end. */
static void note_completion(Tag* t) {
    atomic_store(&t->in_completion, 1);
    atomic_store(&t->completion_seq, atomic_fetch_add(&sequence, 1) + 1);
    atomic_store(&t->completion_on_main, pthread_main_np() != 0);
    atomic_store(&t->completion_after_return, atomic_load(&t->returned));
    atomic_store(&t->completion_thread, tid());
    atomic_store(&t->t_cb, now());
    atomic_fetch_add(&t->completions, 1);
}
static void finish_completion(Tag* t) { atomic_store(&t->in_completion, 0); }
static void on_release(void* user_data) {
    Tag* t = tag_of(user_data);
    if (atomic_load(&t->in_completion)) atomic_store(&t->release_during_completion, 1);
    atomic_store(&t->release_on_main, pthread_main_np() != 0);
    atomic_store(&t->release_seq, atomic_fetch_add(&sequence, 1) + 1);
    atomic_store(&t->release_thread, tid());
    if (!atomic_load(&t->returned)) atomic_store(&t->release_before_return, 1);
    atomic_fetch_add(&t->releases, 1);
}
static void on_echo(void* user_data, int32_t value, int32_t is_main) {
    (void)is_main;
    atomic_store(&tag_of(user_data)->value, value);
    note_completion(tag_of(user_data));
    finish_completion(tag_of(user_data));
}
static void on_dialog(void* user_data, uint64_t request_id, int32_t error, int32_t button) {
    (void)request_id; (void)button;
    atomic_store(&tag_of(user_data)->error, error);
    note_completion(tag_of(user_data));
    finish_completion(tag_of(user_data));
}
static void on_share(void* user_data, int32_t error, int32_t chosen, ntk_string* title) {
    (void)chosen;
    atomic_store(&tag_of(user_data)->error, error);
    note_completion(tag_of(user_data));
    ntk_string_free(title);
    finish_completion(tag_of(user_data));
}
/* Counted too, so that a rejected notification request that still calls back is caught. */
static void on_notification_done(void* user_data, int32_t error, int32_t granted) {
    (void)granted;
    atomic_store(&tag_of(user_data)->error, error);
    note_completion(tag_of(user_data));
    finish_completion(tag_of(user_data));
}
static void on_notification_event(void* user_data, int32_t kind, ntk_string* a, ntk_string* b, ntk_string* c, int32_t launch) {
    (void)kind; (void)launch; ntk_string_free(a); ntk_string_free(b); ntk_string_free(c);
    note_completion(tag_of(user_data));
    finish_completion(tag_of(user_data));
}

/* Runs the main run loop (and so the main queue) for the given time, even when it has no sources. */
static void pump(double seconds) {
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + seconds;
    while (CFAbsoluteTimeGetCurrent() < end) {
        if (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false) == kCFRunLoopRunFinished) usleep(10000);
    }
}

static void mark_returned(int tag) { atomic_store(&tags[tag].returned, 1); }

static atomic_ullong worker_thread;

static void* off_main(void* arg) {
    (void)arg;
    atomic_store(&worker_thread, tid());
    int32_t is_main = -1; uint64_t t = 0; int32_t has_app = -1;
    ntk_probe_thread_info(&is_main, &t, &has_app);
    CHECK(is_main == 0 && t != 0, "thread_info off main: is_main=%d tid!=0", is_main);
    ntk_notification_error e = ntk_notification_install();
    CHECK(e == NTK_NOTIFICATION_ERROR_WRONG_THREAD, "install off main -> %d (WRONG_THREAD 16)", e);
    e = ntk_probe_notification_install_at(1);
    CHECK(e == NTK_NOTIFICATION_ERROR_WRONG_THREAD, "install_at(1) off main -> %d (WRONG_THREAD 16)", e);
    /* While this thread is inside the entry (and, with the hook, sleeping there), main is pumping. */
    atomic_store(&tags[2].t_call, now());
    ntk_probe_error r = ntk_probe_echo_async(22, 0, on_echo, (void*)(intptr_t)2, on_release);
    atomic_store(&tags[2].t_ret, now());
    mark_returned(2);
    CHECK(r == 0, "echo from a thread accepted");
    if (has_app == 0) {
        uint64_t id = 0;
        atomic_store(&tags[14].t_call, now());
        ntk_dialog_error d = ntk_dialog_show_alert_async("smoke", NULL, "OK", NULL, 0, on_dialog, (void*)(intptr_t)14, on_release, &id);
        atomic_store(&tags[14].t_ret, now());
        mark_returned(14);
        CHECK(d == 0, "dialog from a thread accepted (no NSApp: completes with SHOW_FAILED, no UI)");
    }
    /* A rejection from this thread: release on this thread, before the return. */
    r = ntk_probe_echo_async(0, 0, NULL, (void*)(intptr_t)18, on_release);
    mark_returned(18);   /* the rejection's release must have come before this, on this thread */
    CHECK(r == NTK_PROBE_ERROR_INVALID_PARAMETER && atomic_load(&tags[18].release_before_return) == 1 &&
          atomic_load(&tags[18].release_thread) == atomic_load(&worker_thread),
          "rejected from a thread: release before the return, on the calling thread");
    return NULL;
}

/* A call made on main: once, on main, after the return, release after the completion. */
static void expect_done(int tag, const char* what) {
    Tag* t = &tags[tag];
    int after = atomic_load(&t->release_seq) > atomic_load(&t->completion_seq) && !atomic_load(&t->release_during_completion);
    CHECK(atomic_load(&t->completions) == 1 && atomic_load(&t->releases) == 1 && atomic_load(&t->completion_on_main) &&
          atomic_load(&t->release_on_main) && atomic_load(&t->completion_after_return) && after,
          "%s: completion=%d release=%d completion-on-main=%d release-on-main=%d after-return=%d release-after-completion=%d",
          what, atomic_load(&t->completions), atomic_load(&t->releases), atomic_load(&t->completion_on_main),
          atomic_load(&t->release_on_main), atomic_load(&t->completion_after_return), after);
}

/* A call made on another thread: once, on main (not synchronously on the calling thread), release after
   the completion. The times are information: the caller's code after the call is not ordered. */
static void expect_done_from_thread(int tag, const char* what) {
    Tag* t = &tags[tag];
    double inside = (atomic_load(&t->t_ret) - atomic_load(&t->t_call)) * 1000;
    double lead = (atomic_load(&t->t_cb) - atomic_load(&t->t_ret)) * 1000;
    int after = atomic_load(&t->release_seq) > atomic_load(&t->completion_seq) && !atomic_load(&t->release_during_completion);
    CHECK(atomic_load(&t->completions) == 1 && atomic_load(&t->releases) == 1 && atomic_load(&t->completion_on_main) &&
          atomic_load(&t->release_on_main) && atomic_load(&t->completion_thread) != atomic_load(&worker_thread) &&
          atomic_load(&t->release_thread) != atomic_load(&worker_thread) && after,
          "%s: completion=%d release=%d completion-on-main=%d release-on-main=%d not-on-caller=%d release-after-completion=%d "
          "(info: entry %.0f ms, completion %.1f ms after the caller saw the return)",
          what, atomic_load(&t->completions), atomic_load(&t->releases), atomic_load(&t->completion_on_main),
          atomic_load(&t->release_on_main), atomic_load(&t->completion_thread) != atomic_load(&worker_thread),
          after, inside, lead);
}

/* A call made on main and rejected: the caller marks the return right after the call; release came
   before that, on main (the calling thread), exactly once; no completion or event, even later. */
static void expect_rejected(int tag, int32_t got, int32_t want, const char* what) {
    Tag* t = &tags[tag];
    mark_returned(tag);
    pump(0.05);   /* a wrongly queued completion or event would run here */
    CHECK(got == want && atomic_load(&t->completions) == 0 && atomic_load(&t->releases) == 1 &&
          atomic_load(&t->release_before_return) && atomic_load(&t->release_on_main),
          "%s -> %d (want %d), completion/event=%d release=%d before-return=%d on-caller(main)=%d", what, got, want,
          atomic_load(&t->completions), atomic_load(&t->releases), atomic_load(&t->release_before_return),
          atomic_load(&t->release_on_main));
}

static void expect_redacted(const char* input, const char* want, const char* what) {
    ntk_string* s = ntk_probe_redact_path(input);
    const char* got = s ? ntk_string_data(s) : "NULL";
    CHECK(strcmp(got, want) == 0, "redact %s -> %s", what, got);
    ntk_string_free(s);
}

int main(void) {
    const char* delay = getenv("NTK_PROBE_ENTRY_DELAY_MS");
    entry_delay = delay ? atof(delay) : 0;
    printf("entry delay hook: %.0f ms\n", entry_delay);
    CHECK(ntk_version() == NTK_VERSION, "ntk_version -> 0x%06x", ntk_version());

    int32_t is_main = -1; uint64_t t = 0; int32_t has_app = -1;
    CHECK(ntk_probe_thread_info(&is_main, &t, &has_app) == 0 && is_main == 1, "thread_info on main: is_main=%d has_nsapp=%d", is_main, has_app);
    CHECK(ntk_probe_thread_info(NULL, NULL, NULL) == 0, "thread_info with NULL outs");

    /* echo: accepted on main and from a thread */
    ntk_probe_error r = ntk_probe_echo_async(11, 0, on_echo, (void*)(intptr_t)1, on_release);
    mark_returned(1);
    CHECK(r == 0 && atomic_load(&tags[1].completions) == 0, "echo on main accepted, nothing called inside");
    pthread_t th;
    pthread_create(&th, NULL, off_main, NULL);
    pump(1.0 + entry_delay / 1000 * 2);   /* main drains its queue while the thread is inside the entries */
    pthread_join(th, NULL);
    expect_done(1, "echo on main");
    CHECK(atomic_load(&tags[1].value) == 11, "echo value 11 -> %d", atomic_load(&tags[1].value));
    r = ntk_probe_echo_async(13, 200, on_echo, (void*)(intptr_t)13, on_release);
    mark_returned(13);
    pump(0.1);
    CHECK(r == 0 && atomic_load(&tags[13].completions) == 0, "echo with 200 ms delay: not yet after 100 ms");
    pump(0.5);
    expect_done(13, "echo with 200 ms delay");
    CHECK(atomic_load(&tags[18].completions) == 0 && atomic_load(&tags[18].releases) == 1, "rejected from a thread: no completion later, release once");
    expect_done_from_thread(2, "echo from a thread");
    if (has_app == 0) {
        expect_done_from_thread(14, "dialog from a thread");
        CHECK(atomic_load(&tags[14].error) == NTK_DIALOG_ERROR_SHOW_FAILED, "dialog from a thread error -> %d (SHOW_FAILED 10)", atomic_load(&tags[14].error));
    }
    r = ntk_probe_echo_async(0, 0, NULL, (void*)(intptr_t)3, on_release);
    expect_rejected(3, r, NTK_PROBE_ERROR_INVALID_PARAMETER, "echo NULL callback");

    /* notifications: no app bundle -> NOT_SUPPORTED, UNUserNotificationCenter untouched (no crash) */
    ntk_notification_error e = ntk_notification_install();
    CHECK(e == NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "install on main without a bundle -> %d (NOT_SUPPORTED 3)", e);
    e = ntk_probe_notification_install_at(2);
    CHECK(e == NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "install_at(2) without a bundle -> %d (NOT_SUPPORTED 3)", e);
    e = ntk_probe_notification_install_at(9);
    CHECK(e == NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, "install_at(9) -> %d (INVALID_PARAMETER 1)", e);
    e = ntk_probe_notification_install_at(1);
    CHECK(e == NTK_NOTIFICATION_ERROR_NONE, "install_at(1) on main registers the observer -> %d", e);
    ntk_probe_notification_listener* listener = (ntk_probe_notification_listener*)1;
    e = ntk_probe_notification_add_listener(on_notification_event, (void*)(intptr_t)4, on_release, &listener);
    expect_rejected(4, e, NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "add_listener");
    CHECK(listener == NULL, "add_listener out is NULL");
    e = ntk_probe_notification_request_permission(on_notification_done, (void*)(intptr_t)5, on_release);
    expect_rejected(5, e, NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "request_permission");
    e = ntk_probe_notification_schedule_marked(5, "smoke", "smoke", on_notification_done, (void*)(intptr_t)6, on_release);
    expect_rejected(6, e, NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "schedule_marked");
    e = ntk_probe_notification_get_authorization_status(on_notification_done, (void*)(intptr_t)15, on_release);
    expect_rejected(15, e, NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, "get_authorization_status");
    ntk_string* id = (ntk_string*)1; ntk_string* action = (ntk_string*)1;
    e = ntk_probe_notification_get_launch_response(&id, &action);
    CHECK(e == NTK_NOTIFICATION_ERROR_NOT_SUPPORTED && id == NULL && action == NULL, "get_launch_response -> %d, outs NULL", e);
    ntk_string* nd = ntk_probe_notification_describe();
    CHECK(nd && strstr(ntk_string_data(nd), "installed=0"), "notification_describe: %s", nd ? ntk_string_data(nd) : "NULL");
    ntk_string_free(nd);

    /* dialog and share: input rejections, then (only while NSApp does not exist) the no-UI failures */
    uint64_t rid = 99;
    ntk_dialog_error de = ntk_dialog_show_alert_async("t", NULL, "OK", NULL, 0, NULL, (void*)(intptr_t)7, on_release, &rid);
    expect_rejected(7, de, NTK_DIALOG_ERROR_INVALID_PARAMETER, "dialog NULL callback");
    CHECK(rid == 0, "dialog rejected: request id 0");
    de = ntk_dialog_show_alert_async("t", NULL, "", NULL, 0, on_dialog, (void*)(intptr_t)8, on_release, NULL);
    expect_rejected(8, de, NTK_DIALOG_ERROR_INVALID_PARAMETER, "dialog empty positive text");
    de = ntk_probe_dialog_show_alert_gcd_async(NULL, NULL, "OK", NULL, 0, on_dialog, (void*)(intptr_t)16, on_release, NULL);
    expect_rejected(16, de, NTK_DIALOG_ERROR_INVALID_PARAMETER, "dialog (A control) NULL title");
    const char bad[] = { (char)0xC3, (char)0x28, 0 };
    ntk_share_error se = ntk_share_show_async(bad, 0, on_share, (void*)(intptr_t)9, on_release);
    expect_rejected(9, se, NTK_SHARE_ERROR_INVALID_PARAMETER, "share invalid UTF-8");
    se = ntk_share_show_async(NULL, 0, on_share, (void*)(intptr_t)10, on_release);
    expect_rejected(10, se, NTK_SHARE_ERROR_EMPTY_CONTENT, "share NULL text");

    ntk_probe_thread_info(NULL, NULL, &has_app);
    if (has_app == 0) {
        de = ntk_dialog_show_alert_async("smoke", NULL, "OK", NULL, 0, on_dialog, (void*)(intptr_t)11, on_release, &rid);
        mark_returned(11);
        CHECK(de == 0 && rid != 0, "dialog accepted without NSApp, id=%llu", (unsigned long long)rid);
        de = ntk_probe_dialog_show_alert_gcd_async("smoke", NULL, "OK", NULL, 0, on_dialog, (void*)(intptr_t)17, on_release, NULL);
        mark_returned(17);
        CHECK(de == 0, "dialog (A control) accepted without NSApp");
        se = ntk_share_show_async("smoke", 0, on_share, (void*)(intptr_t)12, on_release);
        mark_returned(12);
        CHECK(se == 0, "share accepted without NSApp");
        pump(0.5);
        expect_done(11, "dialog without NSApp");
        CHECK(atomic_load(&tags[11].error) == NTK_DIALOG_ERROR_SHOW_FAILED, "dialog error -> %d (SHOW_FAILED 10)", atomic_load(&tags[11].error));
        expect_done(17, "dialog (A control) without NSApp");
        CHECK(atomic_load(&tags[17].error) == NTK_DIALOG_ERROR_SHOW_FAILED, "dialog (A control) error -> %d (SHOW_FAILED 10)", atomic_load(&tags[17].error));
        expect_done(12, "share without NSApp");
        CHECK(atomic_load(&tags[12].error) == NTK_SHARE_ERROR_NOT_FOREGROUND, "share error -> %d (NOT_FOREGROUND 6)", atomic_load(&tags[12].error));
    } else {
        printf("skip dialog/share completion checks: NSApp exists\n");
    }
    ntk_probe_thread_info(NULL, NULL, &has_app);
    CHECK(has_app == 0, "NSApp still not created by the library");

    /* Path redaction (what describe and the logs use). The home comes from the user database, so the
       result is the same with HOME pointing elsewhere (run.sh runs this with HOME set to a fake container). */
    const char* home = getenv("NTK_SMOKE_REAL_HOME");   /* set by run.sh from the user database; never printed */
    char in[1024];
    expect_redacted("/Users/someone/Desktop/out/Unity NativeToolkit.app", "Unity NativeToolkit.app", "an app bundle path");
    expect_redacted("/Users/someone/Desktop/out/Foo.app/Contents/Frameworks/NtkProbeMac.framework/Versions/A/NtkProbeMac",
                    "Foo.app/Contents/Frameworks/NtkProbeMac.framework/Versions/A/NtkProbeMac", "inside an app");
    expect_redacted("/private/tmp/x-Users-someone/out/NtkProbeMac.framework/Versions/A/NtkProbeMac",
                    "…/NtkProbeMac.framework/Versions/A/NtkProbeMac", "a framework outside an app");
    expect_redacted("/Users/someone/Library/Logs/other.log", "…/other.log", "another user's file");
    if (home) {
        snprintf(in, sizeof in, "%s/Library/Containers/com.jonghyunkim.nativetoolkit.probe1a9/Data/ntk-1a9.log", home);
        expect_redacted(in, "~/Library/Containers/com.jonghyunkim.nativetoolkit.probe1a9/Data/ntk-1a9.log", "the container log under the real home");
    }
    CHECK(ntk_probe_redact_path(NULL) == NULL, "redact NULL -> NULL");

    ntk_string* d = ntk_probe_describe();
    const char* dt = d ? ntk_string_data(d) : "";
    CHECK(d && strstr(dt, "app-bundle=0") && strstr(dt, "nsapp=nil"), "describe: %s", dt);
    CHECK(d && !strstr(dt, "/Users/") && !(home && strstr(dt, home)), "describe has no home path");
    ntk_string_free(d);
    ntk_string_free(NULL);
    CHECK(ntk_string_data(NULL) == NULL && ntk_string_size(NULL) == 0, "NULL string handle");

    printf("%s\n", failures == 0 ? "SMOKE PASS" : "SMOKE FAIL");
    return failures == 0 ? 0 : 1;
}
