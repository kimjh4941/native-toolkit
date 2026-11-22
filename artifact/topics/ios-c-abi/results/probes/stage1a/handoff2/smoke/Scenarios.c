/* Hand-off 2 smoke: ntk_notification_install and the notification probe functions from plain C. */
#include "Scenarios.h"

#include <IosLibraryCApi/NativeToolkitC/Common.h>
#include <IosLibraryCApi/NativeToolkitC/Notification.h>
#include <IosLibraryCApi/NativeToolkitC/ProbeNotification.h>
#include <IosLibraryCApi/NativeToolkitC/ProbeDialog.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>

static int failures;
static int releases, release_on_main = 1, returned;
static ntk_notification_error off_main = -1;
static void (*done)(int);

#define CHECK(cond) do { if (!(cond)) { failures++; printf("SMOKE FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); } } while (0)

static void on_event(void* user_data, ntk_probe_notification_event_kind kind, ntk_string* identifier, ntk_string* action,
                     ntk_string* text, int32_t is_launch) {
    (void)user_data;
    printf("SMOKE event kind=%d id=%s launch=%d\n", kind, identifier ? ntk_string_data(identifier) : "(null)", is_launch);
    ntk_string_free(identifier); ntk_string_free(action); ntk_string_free(text);
}

static void on_release(void* user_data) {
    (void)user_data;
    releases++;
    release_on_main = release_on_main && pthread_main_np();
    printf("SMOKE release main=%d returned=%d\n", pthread_main_np(), returned);
}

static void* install_off_main(void* arg) {
    (void)arg;
    off_main = ntk_notification_install();
    return NULL;
}

void smoke_install(void) {
    pthread_t thread;
    pthread_create(&thread, NULL, install_off_main, NULL);
    pthread_join(thread, NULL);
    ntk_notification_error on_main = ntk_notification_install();
    printf("SMOKE install off main=%d on main=%d again=%d\n", off_main, on_main, ntk_notification_install());
    CHECK(off_main == NTK_NOTIFICATION_ERROR_WRONG_THREAD);
    CHECK(on_main == NTK_NOTIFICATION_ERROR_NONE);
}

static void finish(void* context) {
    (void)context;
    CHECK(releases == 1 && release_on_main);
    done(failures);
}

void smoke_run(void (*finished)(int)) {
    done = finished;
    ntk_probe_notification_listener* listener = NULL;
    CHECK(ntk_probe_notification_add_listener(on_event, NULL, on_release, &listener) == NTK_NOTIFICATION_ERROR_NONE && listener);
    ntk_string* identifier = (ntk_string*)1;
    ntk_string* action = (ntk_string*)1;
    CHECK(ntk_probe_notification_get_launch_response(&identifier, &action) == NTK_NOTIFICATION_ERROR_NONE);
    printf("SMOKE launch response id=%s action=%s\n", identifier ? ntk_string_data(identifier) : "(null)", action ? ntk_string_data(action) : "(null)");
    CHECK(identifier == NULL && action == NULL);
    ntk_probe_notification_listener_remove(listener);
    returned = 1;
    CHECK(releases == 0);
    CHECK(ntk_probe_dialog_cancel(12345) == NTK_PROBE_DIALOG_ERROR_NONE);   /* hand-off 1 functions are still there */
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), NULL, finish);
}
