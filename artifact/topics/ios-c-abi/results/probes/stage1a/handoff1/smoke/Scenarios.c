/* Hand-off 1 smoke: Dialog and Share probe functions called from plain C. */
#include "Scenarios.h"

#include <IosLibraryCApi/NativeToolkitC/Common.h>
#include <IosLibraryCApi/NativeToolkitC/Probe.h>
#include <IosLibraryCApi/NativeToolkitC/ProbeDialog.h>
#include <IosLibraryCApi/NativeToolkitC/ProbeShare.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>

typedef struct request_state {
    const char* name;
    int callbacks, releases, returned, callback_before_return, on_main;
    int release_before_return;
    ntk_probe_dialog_error error;
    uint64_t id;
} request_state;

static int failures;
static void (*hide)(int);
static void (*done)(int);
static request_state shown = {"shown"}, early = {"early"}, background = {"background"}, rejected = {"rejected"};

#define CHECK(cond) do { if (!(cond)) { failures++; printf("SMOKE FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); } } while (0)

static void on_dialog(void* user_data, uint64_t request_id, ntk_probe_dialog_error error, uint32_t system_code,
                      ntk_probe_dialog_button button) {
    request_state* s = (request_state*)user_data;
    s->callbacks++;
    s->callback_before_return = !s->returned;
    s->on_main = pthread_main_np();
    s->error = error;
    printf("SMOKE dialog %s id=%llu error=%d system_code=%u button=%d main=%d\n", s->name,
           (unsigned long long)request_id, error, system_code, button, s->on_main);
}

static void step_background(void);
static void step_finish(void);

static void on_release(void* user_data) {
    request_state* s = (request_state*)user_data;
    s->releases++;
    s->release_before_return = !s->returned;
    printf("SMOKE release %s main=%d before_return=%d\n", s->name, pthread_main_np(), s->release_before_return);
    if (s == &shown) step_background();
    else if (s == &background) step_finish();
}

static void cancel_shown(void* context) {
    (void)context;
    CHECK(ntk_probe_dialog_cancel(shown.id) == NTK_PROBE_DIALOG_ERROR_NONE);
}

static void* show_and_cancel_on_a_thread(void* arg) {
    (void)arg;
    CHECK(ntk_probe_dialog_show_alert("early", NULL, NULL, NULL, on_dialog, &early, on_release, &early.id) == NTK_PROBE_DIALOG_ERROR_NONE);
    early.returned = 1;
    CHECK(ntk_probe_dialog_cancel(early.id) == NTK_PROBE_DIALOG_ERROR_NONE);
    CHECK(ntk_probe_share_text(NULL, NULL, &rejected, on_release) == NTK_PROBE_SHARE_ERROR_INVALID_PARAMETER);
    rejected.returned = 1;
    CHECK(rejected.releases == 1 && rejected.release_before_return);
    return NULL;
}

/* 2: not in the foreground (the key window is hidden). */
static void step_background(void) {
    CHECK(shown.callbacks == 1 && shown.releases == 1 && shown.error == NTK_PROBE_DIALOG_ERROR_CANCELED && shown.on_main);
    hide(1);
    CHECK(ntk_probe_dialog_show_alert("hidden", NULL, NULL, NULL, on_dialog, &background, on_release, &background.id) == NTK_PROBE_DIALOG_ERROR_NONE);
    background.returned = 1;
}

static void step_finish(void) {
    hide(0);
    CHECK(background.callbacks == 1 && background.error == NTK_PROBE_DIALOG_ERROR_NOT_FOREGROUND && background.on_main);
    CHECK(early.callbacks == 1 && early.releases == 1 && early.error == NTK_PROBE_DIALOG_ERROR_CANCELED);
    CHECK(!shown.callback_before_return && !background.callback_before_return);
    done(failures);
}

void smoke_run(void (*set_window_hidden)(int), void (*finished)(int)) {
    hide = set_window_hidden;
    done = finished;
    printf("SMOKE ntk_version=0x%06x last_system_code=%u\n", ntk_version(), ntk_last_system_code());
    CHECK(ntk_version() == NTK_VERSION);

    /* 1: shown, then cancelled from main one second later; another one cancelled at once on a thread. */
    CHECK(ntk_probe_dialog_show_alert("Smoke", "cancelled after 1 s", "Yes", "No", on_dialog, &shown, on_release, &shown.id) == NTK_PROBE_DIALOG_ERROR_NONE);
    shown.returned = 1;
    CHECK(shown.callbacks == 0);
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), NULL, cancel_shown);
    pthread_t thread;
    pthread_create(&thread, NULL, show_and_cancel_on_a_thread, NULL);
    pthread_join(thread, NULL);
}
