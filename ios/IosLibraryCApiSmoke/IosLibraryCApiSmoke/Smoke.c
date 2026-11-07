/* The smoke of the iOS C ABI, its C part (C ABI design part 2, 12.4; README 7).
 *
 * The app is built from the two distributed xcframeworks only: this file reads the public headers
 * through the framework, as a C user does, and calls the C functions. It has no Swift code, so it
 * also shows that the C ABI runs without the app embedding a Swift runtime. Each asynchronous
 * request counts its completions and releases, which must each come once, on the main thread.
 */
#include "Smoke.h"

#include <IosLibraryCApi/NativeToolkitC/Clipboard.h>
#include <IosLibraryCApi/NativeToolkitC/Dialog.h>
#include <IosLibraryCApi/NativeToolkitC/Notification.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Text with a four-byte UTF-8 character, written and read back. */
static const char k_text[] = "ntk smoke \xF0\x9F\x99\x82 text";
/* How long the dialog stays up before it is cancelled. */
static const int64_t k_dialog_seconds = 1500 * NSEC_PER_MSEC;

/* Counted on the main thread only: a call off it ends the app first (main_thread_only). Atomic all the
   same, so that a wrong thread cannot also make the counts a data race. */
typedef struct smoke_request {
    const char* name;
    atomic_int completions;
    atomic_int releases;
} smoke_request;

enum { CREATE, COPY, READ, REMOVE, DIALOG, LISTENER, REQUEST_COUNT };

static smoke_request g_requests[REQUEST_COUNT] = {
    {"clipboard create", 0, 0}, {"clipboard copy", 0, 0}, {"clipboard read", 0, 0},
    {"clipboard remove", 0, 0}, {"dialog", 0, 0}, {"notification listener", 0, 0},
};
static int g_failures;
static int g_finished;
static smoke_finished_fn g_finished_fn;
static char g_pasteboard_name[96];
static ntk_clipboard_scope g_scope;
static uint64_t g_dialog_id;

static void report(int ok, const char* step, const char* format, ...) {
    char detail[256];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(detail, sizeof detail, format, arguments);
    va_end(arguments);
    if (!ok) {
        g_failures++;
    }
    printf("SMOKE %s %s: %s\n", ok ? "PASS" : "FAIL", step, detail);
    fflush(stdout);
}

/* Every callback and release must come on the main thread. One that does not ends the app at once,
   before it touches any state the main thread uses. */
static void main_thread_only(const smoke_request* request, const char* what) {
    if (!pthread_main_np()) {
        printf("SMOKE FAIL callbacks: %s: %s off the main thread\nSMOKE RESULT FAIL\n", request->name, what);
        fflush(stdout);
        _exit(1);
    }
}

static void completed(smoke_request* request) {
    main_thread_only(request, "a completion");
    atomic_fetch_add(&request->completions, 1);
}

static void NTK_CALL released(void* user_data) {
    smoke_request* request = user_data;
    main_thread_only(request, "a release");
    atomic_fetch_add(&request->releases, 1);
}

static void verdict(void* context) {
    (void)context;
    for (int index = 0; index < REQUEST_COUNT; index++) {
        smoke_request* request = &g_requests[index];
        int completions = atomic_load(&request->completions);
        int releases = atomic_load(&request->releases);
        report(completions == (index == LISTENER ? 0 : 1) && releases == 1, "callbacks",
               "%s: %d completions, %d releases, all on the main thread", request->name, completions, releases);
    }
    g_finished_fn(g_failures);
}

static void finish(void) {
    if (g_finished) {
        return;
    }
    g_finished = 1;
    /* Releases may come right after the completion that ended the last step. */
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), NULL, verdict);
}

static void watchdog(void* context) {
    (void)context;
    if (!g_finished) {
        report(0, "timeout", "the steps did not end within 60 seconds");
        finish();
    }
}

/* --- dialog ------------------------------------------------------------------------------------ */

static void NTK_CALL dialog_done(void* user_data, uint64_t request_id, ntk_dialog_error error, uint32_t system_code,
                                 ntk_dialog_result* result) {
    completed(user_data);
    report(error == NTK_DIALOG_ERROR_CANCELED && result == NULL && request_id == g_dialog_id, "dialog",
           "completion %d for request %llu (system code %u)", (int)error, (unsigned long long)request_id, system_code);
    ntk_dialog_result_free(result);
    finish();
}

static void cancel_dialog(void* context) {
    (void)context;
    ntk_dialog_error error = ntk_dialog_cancel(g_dialog_id);
    report(error == NTK_DIALOG_ERROR_NONE, "dialog cancel", "returned %d", (int)error);
}

static void show_dialog(void) {
    ntk_dialog_alert_request request;
    memset(&request, 0, sizeof request);
    request.struct_size = sizeof request;
    request.title = "IosLibraryCApiSmoke";
    request.message = "Shown from C; the smoke cancels it.";
    ntk_dialog_error error = ntk_dialog_show_alert_async(&request, dialog_done, &g_requests[DIALOG], released, &g_dialog_id);
    report(error == NTK_DIALOG_ERROR_NONE && g_dialog_id != 0, "dialog show", "returned %d, request %llu", (int)error,
           (unsigned long long)g_dialog_id);
    if (error != NTK_DIALOG_ERROR_NONE) {
        finish();
        return;
    }
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, k_dialog_seconds), dispatch_get_main_queue(), NULL, cancel_dialog);
}

/* --- clipboard --------------------------------------------------------------------------------- */

static void NTK_CALL removed(void* user_data, ntk_clipboard_error error, uint32_t system_code) {
    completed(user_data);
    report(error == NTK_CLIPBOARD_ERROR_NONE, "clipboard remove", "completion %d (system code %u)", (int)error, system_code);
    show_dialog();
}

static void remove_pasteboard(void) {
    ntk_clipboard_error error = ntk_clipboard_remove_pasteboard_async(&g_scope, removed, &g_requests[REMOVE], released);
    if (error != NTK_CLIPBOARD_ERROR_NONE) {
        report(0, "clipboard remove", "returned %d", (int)error);
        show_dialog();
    }
}

static void NTK_CALL read_done(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                               ntk_clipboard_read_result* result) {
    completed(user_data);
    size_t size = 0;
    size_t items = result != NULL ? ntk_clipboard_read_result_item_count(result) : 0;
    const char* text = result != NULL ? ntk_clipboard_read_result_item_text_at(result, 0, &size) : NULL;
    int same = text != NULL && size == strlen(k_text) && memcmp(text, k_text, size) == 0;
    report(error == NTK_CLIPBOARD_ERROR_NONE && result != NULL && items == 1 && same, "clipboard read",
           "completion %d (system code %u), %zu items, %s", (int)error, system_code, items,
           same ? "the text written" : "not the text written");
    ntk_clipboard_read_result_free(result);
    remove_pasteboard();
}

static void NTK_CALL copied(void* user_data, ntk_clipboard_error error, uint32_t system_code) {
    completed(user_data);
    report(error == NTK_CLIPBOARD_ERROR_NONE, "clipboard copy", "completion %d (system code %u)", (int)error, system_code);
    ntk_clipboard_error started = ntk_clipboard_read_async(&g_scope, read_done, &g_requests[READ], released);
    if (started != NTK_CLIPBOARD_ERROR_NONE) {
        report(0, "clipboard read", "returned %d", (int)started);
        remove_pasteboard();
    }
}

static void NTK_CALL created(void* user_data, ntk_clipboard_error error, uint32_t system_code, ntk_string* name) {
    completed(user_data);
    const char* given = ntk_string_data(name);
    report(error == NTK_CLIPBOARD_ERROR_NONE && given != NULL && strcmp(given, g_pasteboard_name) == 0,
           "clipboard create", "completion %d (system code %u)", (int)error, system_code);
    ntk_string_free(name);
    ntk_clipboard_write_content content;
    memset(&content, 0, sizeof content);
    content.struct_size = sizeof content;
    content.kind = NTK_CLIPBOARD_CONTENT_PLAIN_TEXT;
    content.text = k_text;
    ntk_clipboard_error started = ntk_clipboard_copy_async(&content, NULL, &g_scope, copied, &g_requests[COPY], released);
    if (started != NTK_CLIPBOARD_ERROR_NONE) {
        report(0, "clipboard copy", "returned %d", (int)started);
        remove_pasteboard();
    }
}

static void start_clipboard(void) {
    /* A named pasteboard of its own: the smoke never reads or writes the general one, which on a
       device holds what the user copied (agent-rules/device-testing.md). */
    snprintf(g_pasteboard_name, sizeof g_pasteboard_name, "com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke.%d", (int)getpid());
    memset(&g_scope, 0, sizeof g_scope);
    g_scope.struct_size = sizeof g_scope;
    g_scope.kind = NTK_CLIPBOARD_SCOPE_NAMED;
    g_scope.name = g_pasteboard_name;
    ntk_clipboard_error error = ntk_clipboard_create_pasteboard_async(NTK_CLIPBOARD_SCOPE_NAMED, g_pasteboard_name, created,
                                                                     &g_requests[CREATE], released);
    if (error != NTK_CLIPBOARD_ERROR_NONE) {
        report(0, "clipboard create", "returned %d", (int)error);
        show_dialog();
    }
}

/* --- notification ------------------------------------------------------------------------------ */

static void NTK_CALL interaction(void* user_data, ntk_notification_interaction* event) {
    (void)event;
    completed(user_data);
}

void smoke_run(int32_t install_result, smoke_finished_fn finished) {
    g_finished_fn = finished;
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), NULL, watchdog);

    uint32_t version = ntk_version();
    report(version == NTK_VERSION, "version", "ntk_version() is 0x%06x, the header says 0x%06x", version, NTK_VERSION);

    report(install_result == NTK_NOTIFICATION_ERROR_NONE, "notification install", "returned %d at launch", (int)install_result);
    /* A listener is NOT_INITIALIZED until the delegate is installed: this shows the install took. */
    ntk_notification_listener* listener = NULL;
    ntk_notification_error error = ntk_notification_add_interaction_listener(interaction, &g_requests[LISTENER], released,
                                                                             &listener);
    report(error == NTK_NOTIFICATION_ERROR_NONE && listener != NULL, "notification listener", "returned %d", (int)error);
    ntk_notification_listener_remove(listener);

    start_clipboard();
}
