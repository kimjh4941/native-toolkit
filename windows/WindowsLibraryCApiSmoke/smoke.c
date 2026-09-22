/*
 * CT-21 of the stage 5 design: the C ABI used the way a consumer uses it.
 *
 * Built from the public headers and the import library alone, against the
 * real WindowsLibraryCApi DLL: once as C (WindowsLibraryCApiSmoke, /TC) and
 * once as C++ (WindowsLibraryCApiSmokeCpp, which includes this file), so both
 * the C declarations and the C linkage a C++ caller gets are exercised. The
 * code is therefore C99 that is also valid C++.
 *
 * What it touches: the real clipboard. The text it writes is marked
 * NTK_CLIPBOARD_WRITE_SENSITIVE, so it stays out of the clipboard history and
 * off other devices, and the text that was there before is put back. When the
 * clipboard holds anything but text, the round trip is skipped rather than
 * overwrite it, unless --overwrite-clipboard is given: then the clipboard is
 * emptied afterwards, and what it held is lost. No dialog is shown and no
 * notification is registered.
 *
 * Exit code 0 when every check passed, 2 when the round trip was skipped.
 */
#include "NativeToolkitC/Common.h"
#include "NativeToolkitC/Dialog.h"
#include "NativeToolkitC/Notification.h"
#include "NativeToolkitC/Clipboard.h"

#include <windows.h>

#include <stdio.h>
#include <string.h>

static int g_failures = 0;
static int g_skipped = 0;
static int g_overwrite = 0;   /* --overwrite-clipboard */

static void check(int condition, const char* what)
{
    printf("%s %s\n", condition ? "ok     " : "FAILED ", what);
    if (!condition) ++g_failures;
}

/* ------------------------------------------------------------------------ */
/* Version and the handles of Common.h                                      */
/* ------------------------------------------------------------------------ */

static void check_version(void)
{
    check(ntk_version() == NTK_VERSION, "ntk_version matches NTK_VERSION of the header");
}

/* ------------------------------------------------------------------------ */
/* Dialog: only what returns before a dialog would show                     */
/* ------------------------------------------------------------------------ */

static void check_dialog(void)
{
    ntk_dialog_alert_request request;
    ntk_dialog_alert_result result = NTK_DIALOG_ALERT_RESULT_OK;
    ntk_string* path = (ntk_string*)1;

    memset(&request, 0, sizeof(request));
    request.struct_size = (uint32_t)sizeof(request);
    request.reserved0 = 1;
    check(ntk_dialog_show_alert(&request, &result) == NTK_DIALOG_ERROR_INVALID_PARAMETER,
          "dialog: a struct with reserved0 set is refused before any dialog");
    check(ntk_dialog_show_open_file(NULL, NULL, 1, &path) == NTK_DIALOG_ERROR_INVALID_PARAMETER && path == NULL,
          "dialog: filters NULL with a count is refused, and the output is NULL");
}

/* ------------------------------------------------------------------------ */
/* Notification: the builder and what needs no registration                 */
/* ------------------------------------------------------------------------ */

static void check_notification(void)
{
    ntk_notification_content* content = NULL;
    size_t index = 99;
    ntk_notification_setting setting = NTK_NOTIFICATION_SETTING_ENABLED;

    check(ntk_notification_content_create(&content) == NTK_NOTIFICATION_ERROR_NONE && content != NULL,
          "notification: content_create");
    check(ntk_notification_content_set_title(content, "caf\xC3\xA9") == NTK_NOTIFICATION_ERROR_NONE,
          "notification: set_title in UTF-8");
    check(ntk_notification_content_add_button(content, "OK", NULL, 1, &index) == NTK_NOTIFICATION_ERROR_NONE && index == 0,
          "notification: add_button hands its index back");
    check(ntk_notification_content_set_scenario(content, 99) == NTK_NOTIFICATION_ERROR_INVALID_PARAMETER,
          "notification: an enum value out of range is refused");
    ntk_notification_content_free(content);

    check(ntk_notification_get_setting(NULL, &setting) == NTK_NOTIFICATION_ERROR_INVALID_PARAMETER,
          "notification: a NULL manager is refused");
    check(ntk_notification_list_count(NULL) == 0, "notification: reading a NULL list reads 0");
}

/* ------------------------------------------------------------------------ */
/* Clipboard: a session on this STA, a round trip, one history completion   */
/* ------------------------------------------------------------------------ */

typedef struct availability_seen {
    int calls;
    ntk_clipboard_error error;
} availability_seen;

static void NTK_CALL on_availability(void* user_data, uint32_t request_id, ntk_clipboard_error error,
                                     uint32_t system_code, int32_t history_enabled, int32_t roaming_enabled)
{
    availability_seen* seen = (availability_seen*)user_data;
    (void)request_id;
    (void)system_code;
    (void)history_enabled;
    (void)roaming_enabled;
    ++seen->calls;
    seen->error = error;
}

/* Runs the message loop of this owner thread until *done or the time is up. */
static void pump_until(const int* done, DWORD milliseconds)
{
    const ULONGLONG deadline = GetTickCount64() + milliseconds;
    while (!*done && GetTickCount64() < deadline) {
        MSG message;
        MsgWaitForMultipleObjects(0, NULL, FALSE, 50, QS_ALLINPUT);
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

/* Whether every format on the clipboard is one of the text formats. */
static int holds_only_text(ntk_clipboard_session* session)
{
    static const char* const text_formats[] = {"CF_UNICODETEXT", "CF_TEXT", "0x0007", "0x0010"};
    ntk_string_list* formats = NULL;
    size_t i, j;
    int only_text = 1;

    if (ntk_clipboard_get_formats(session, &formats) != NTK_CLIPBOARD_ERROR_NONE) return 0;
    for (i = 0; i < ntk_string_list_count(formats); ++i) {
        const char* name = ntk_string_list_at(formats, i, NULL);
        int known = 0;
        for (j = 0; j < sizeof(text_formats) / sizeof(text_formats[0]); ++j) {
            if (strcmp(name, text_formats[j]) == 0) known = 1;
        }
        if (!known) only_text = 0;
    }
    ntk_string_list_free(formats);
    return only_text;
}

static void round_trip_text(ntk_clipboard_session* session)
{
    /* "Smoke: " then e-acute, two CJK characters and an emoji, as UTF-8 bytes. */
    static const char text[] = "Smoke: caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC \xF0\x9F\x98\x80";
    ntk_string* before = NULL;
    ntk_string* after = NULL;
    int32_t present = 0;
    size_t size = 0;

    if (!holds_only_text(session)) {
        if (!g_overwrite) {
            printf("skipped clipboard: the round trip, because the clipboard holds more than text "
                   "(--overwrite-clipboard runs it and empties the clipboard afterwards)\n");
            ++g_skipped;
            return;
        }
    } else {
        /* Only text: keep it, to put it back afterwards. */
        ntk_clipboard_paste_text(session, &before);
    }

    check(ntk_clipboard_copy_text(session, text, NTK_CLIPBOARD_WRITE_SENSITIVE) == NTK_CLIPBOARD_ERROR_NONE,
          "clipboard: copy_text, kept out of the history");
    check(ntk_clipboard_has_format(session, "CF_UNICODETEXT", &present) == NTK_CLIPBOARD_ERROR_NONE && present != 0,
          "clipboard: has_format writes its output");
    check(ntk_clipboard_paste_text(session, &after) == NTK_CLIPBOARD_ERROR_NONE && after != NULL,
          "clipboard: paste_text hands a string back");
    if (after) {
        const char* data = ntk_string_data(after);
        size = ntk_string_size(after);
        check(size == strlen(text) && memcmp(data, text, size) == 0 && data[size] == '\0',
              "clipboard: the text came back unchanged, NUL-terminated");
    }
    ntk_string_free(after);

    if (before) {
        ntk_clipboard_copy_text(session, ntk_string_data(before), NTK_CLIPBOARD_WRITE_SENSITIVE);
        ntk_string_free(before);
    } else {
        ntk_clipboard_clear(session);
    }
}

static void check_clipboard(void)
{
    ntk_clipboard_session_options options;
    ntk_clipboard_session* session = NULL;
    availability_seen seen = {0, NTK_CLIPBOARD_ERROR_NONE};
    uint32_t request_id = 0;
    int never = 0;

    if (FAILED(CoInitializeEx(NULL, COINIT_APARTMENTTHREADED))) {
        check(0, "clipboard: CoInitializeEx as an STA");
        return;
    }
    memset(&options, 0, sizeof(options));
    options.struct_size = (uint32_t)sizeof(options);
    check(ntk_clipboard_session_create(&options, &session) == NTK_CLIPBOARD_ERROR_NONE && session != NULL,
          "clipboard: session_create on an STA");
    if (!session) {
        CoUninitialize();
        return;
    }

    round_trip_text(session);

    check(ntk_clipboard_get_history_availability(session, &on_availability, &seen, &request_id) == NTK_CLIPBOARD_ERROR_NONE,
          "clipboard: get_history_availability is accepted");
    check(seen.calls == 0, "clipboard: the completion did not come inside the call");
    pump_until(&seen.calls, 10000);
    pump_until(&never, 200);   /* long enough for a second completion to show */
    check(seen.calls == 1, "clipboard: the availability completed exactly once");
    printf("        (availability completed with error %d; NOT_FOREGROUND is %d)\n",
           (int)seen.error, (int)NTK_CLIPBOARD_ERROR_NOT_FOREGROUND);

    check(ntk_clipboard_session_close(session) == NTK_CLIPBOARD_ERROR_NONE, "clipboard: session_close");
    check(ntk_clipboard_session_can_close(session) != 0, "clipboard: a closed session can_close");
    ntk_clipboard_session_free(session);
    check(ntk_last_system_code() == 0, "common: the last success left system code 0");
    CoUninitialize();
}

int main(int argc, char** argv)
{
    int i;
    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--overwrite-clipboard") == 0) g_overwrite = 1;
    }
    printf("NativeToolkit C ABI smoke test (%s)\n",
#ifdef __cplusplus
           "C++"
#else
           "C"
#endif
    );
    check_version();
    check_dialog();
    check_notification();
    check_clipboard();
    printf("%s: %d failed, %d skipped\n", g_failures != 0 ? "FAILED" : g_skipped != 0 ? "INCOMPLETE" : "PASSED",
           g_failures, g_skipped);
    return g_failures != 0 ? 1 : g_skipped != 0 ? 2 : 0;
}
