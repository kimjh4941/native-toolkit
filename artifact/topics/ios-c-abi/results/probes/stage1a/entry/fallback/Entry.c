/* Fallback layout (stage 1a): the C entry points. Each one forwards to the table that the Swift
   side registers. Swift code cannot run before main without @_cdecl or @c, so the first call
   looks up the Swift installer class through the Objective-C runtime (no Objective-C source). */
#include "Table.h"
#include "ThreadLocal.h"

#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>

static const ntkc_table* registered;

void ntkc_register(const ntkc_table* table) { registered = table; }

static void install(void* context) {
    (void)context;
    Class installer = objc_getClass("NTKCApiFallbackInstaller");
    if (installer) ((void (*)(Class, SEL))objc_msgSend)(installer, sel_registerName("install"));
}

static const ntkc_table* table(void) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, install);
    return registered;
}

uint32_t ntk_version(void) { return NTK_VERSION; }
uint32_t ntk_last_system_code(void) { return ntkc_tls_get(); }

const char* ntk_string_data(const ntk_string* s) { return table()->string_data(s); }
size_t ntk_string_size(const ntk_string* s) { return table()->string_size(s); }
void ntk_string_free(ntk_string* s) { if (s) table()->string_free(s); }
const uint8_t* ntk_bytes_data(const ntk_bytes* b) { return table()->bytes_data(b); }
size_t ntk_bytes_size(const ntk_bytes* b) { return table()->bytes_size(b); }
void ntk_bytes_free(ntk_bytes* b) { if (b) table()->bytes_free(b); }
size_t ntk_string_list_count(const ntk_string_list* list) { return table()->string_list_count(list); }
const char* ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size) {
    return table()->string_list_at(list, index, out_size);
}
void ntk_string_list_free(ntk_string_list* list) { if (list) table()->string_list_free(list); }

ntk_probe_error ntk_probe_echo(const ntk_probe_echo_request* request, ntk_string** out_text) {
    return table()->probe_echo(request, out_text);
}
ntk_probe_error ntk_probe_clipboard_read_text_async(ntk_probe_text_fn callback, void* user_data,
                                                    ntk_release_fn release, uint64_t* out_request_id) {
    return table()->probe_clipboard_read_text_async(callback, user_data, release, out_request_id);
}
ntk_probe_error ntk_probe_raise_uikit_exception_async(ntk_probe_exception_kind kind, ntk_probe_done_fn callback,
                                                      void* user_data, ntk_release_fn release,
                                                      uint64_t* out_request_id) {
    return table()->probe_raise_uikit_exception_async(kind, callback, user_data, release, out_request_id);
}
