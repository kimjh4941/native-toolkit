/* Stage 1a smoke: calls the C ABI from plain C, through the framework include path. */
#include "Scenarios.h"

#include <IosLibraryCApi/NativeToolkitC/Common.h>
#include <IosLibraryCApi/NativeToolkitC/Probe.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

typedef struct request_state {
    const char* name;
    int callbacks;
    int releases;
    int returned;
    int callback_before_return;
    int callback_on_main;
    int release_on_main;
    int release_before_return;
    char text[64];
} request_state;

static int failures;
static int pending;
static void (*on_finished)(int);
static request_state from_main = {"main"};
static request_state from_thread = {"thread"};
static request_state rejected = {"rejected"};

#define CHECK(cond) do { if (!(cond)) { failures++; printf("SMOKE FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); } } while (0)

static void on_text(void* user_data, uint64_t request_id, ntk_probe_error error, uint32_t system_code, ntk_string* text) {
    request_state* s = (request_state*)user_data;
    s->callbacks++;
    s->callback_before_return = !s->returned;
    s->callback_on_main = pthread_main_np();
    if (text) {
        snprintf(s->text, sizeof s->text, "%s", ntk_string_data(text));
        ntk_string_free(text);
    }
    printf("SMOKE callback %s id=%llu error=%d system_code=%u text=%s main=%d\n", s->name,
           (unsigned long long)request_id, error, system_code, s->text, s->callback_on_main);
}

static void finish_one(void) {
    if (--pending == 0) {
        CHECK(from_main.callbacks == 1 && from_main.releases == 1 && !from_main.callback_before_return);
        CHECK(from_main.callback_on_main && from_main.release_on_main && strcmp(from_main.text, "smoke") == 0);
        CHECK(from_thread.callbacks == 1 && from_thread.releases == 1);
        CHECK(from_thread.callback_on_main && from_thread.release_on_main && strcmp(from_thread.text, "smoke") == 0);
        on_finished(failures);
    }
}

static void on_release(void* user_data) {
    request_state* s = (request_state*)user_data;
    s->releases++;
    s->release_on_main = pthread_main_np();
    s->release_before_return = !s->returned;
    printf("SMOKE release %s main=%d before_return=%d\n", s->name, s->release_on_main, s->release_before_return);
    if (s != &rejected) finish_one();
}

static void* thread_main(void* arg) {
    (void)arg;
    uint64_t id = 0;
    CHECK(ntk_probe_clipboard_read_text_async(on_text, &from_thread, on_release, &id) == NTK_PROBE_ERROR_NONE);
    from_thread.returned = 1;
    /* Rejected on this thread: release runs here, before the function returns. */
    CHECK(ntk_probe_clipboard_read_text_async(NULL, &rejected, on_release, NULL) == NTK_PROBE_ERROR_INVALID_PARAMETER);
    rejected.returned = 1;
    CHECK(rejected.releases == 1 && rejected.release_before_return && !rejected.release_on_main);
    return NULL;
}

void smoke_run_basic(void (*finished)(int)) {
    on_finished = finished;
    printf("SMOKE ntk_version=0x%06x NTK_VERSION=0x%06x last_system_code=%u\n", ntk_version(), NTK_VERSION, ntk_last_system_code());
    CHECK(ntk_version() == NTK_VERSION);

    ntk_probe_echo_request request;
    memset(&request, 0, sizeof request);
    request.struct_size = sizeof request;
    request.text = "h\xc3\xa9llo";
    request.uppercase = 1;
    ntk_string* out = NULL;
    CHECK(ntk_probe_echo(&request, &out) == NTK_PROBE_ERROR_NONE);
    printf("SMOKE echo=%s size=%zu sizeof(request)=%zu\n", out ? ntk_string_data(out) : "(null)", ntk_string_size(out), sizeof request);
    CHECK(out && strcmp(ntk_string_data(out), "H\xc3\x89LLO") == 0);
    ntk_string_free(out);
    request.struct_size = 8;
    CHECK(ntk_probe_echo(&request, &out) == NTK_PROBE_ERROR_INVALID_PARAMETER && out == NULL);

    pending = 2;
    uint64_t id = 0;
    CHECK(ntk_probe_clipboard_read_text_async(on_text, &from_main, on_release, &id) == NTK_PROBE_ERROR_NONE);
    from_main.returned = 1;
    CHECK(from_main.callbacks == 0);

    pthread_t thread;
    pthread_create(&thread, NULL, thread_main, NULL);
    pthread_join(thread, NULL);
}

static void on_done(void* user_data, uint64_t request_id, ntk_probe_error error, uint32_t system_code) {
    (void)user_data; (void)system_code;
    printf("SMOKE exception request %llu completed error=%d (no exception)\n", (unsigned long long)request_id, error);
}

int32_t smoke_raise(int32_t kind) {
    return ntk_probe_raise_uikit_exception_async(kind, on_done, NULL, NULL, NULL);
}
