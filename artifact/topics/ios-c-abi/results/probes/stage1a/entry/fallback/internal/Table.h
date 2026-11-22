/* Fallback layout (stage 1a): the table of Swift receivers that the C entry points call.
   Internal to IosLibraryCApi; visible to Swift through the build-time module map next to it. */
#ifndef NTKC_TABLE_H
#define NTKC_TABLE_H
#include <IosLibraryCApi/NativeToolkitC/Probe.h>

typedef struct ntkc_table {
    uint32_t struct_size;
    uint32_t reserved0;
    const char*    (*string_data)(const ntk_string* s);
    size_t         (*string_size)(const ntk_string* s);
    void           (*string_free)(ntk_string* s);
    const uint8_t* (*bytes_data)(const ntk_bytes* b);
    size_t         (*bytes_size)(const ntk_bytes* b);
    void           (*bytes_free)(ntk_bytes* b);
    size_t         (*string_list_count)(const ntk_string_list* list);
    const char*    (*string_list_at)(const ntk_string_list* list, size_t index, size_t* out_size);
    void           (*string_list_free)(ntk_string_list* list);
    ntk_probe_error (*probe_echo)(const ntk_probe_echo_request* request, ntk_string** out_text);
    ntk_probe_error (*probe_clipboard_read_text_async)(ntk_probe_text_fn callback, void* user_data,
                                                       ntk_release_fn release, uint64_t* out_request_id);
    ntk_probe_error (*probe_raise_uikit_exception_async)(ntk_probe_exception_kind kind, ntk_probe_done_fn callback,
                                                         void* user_data, ntk_release_fn release,
                                                         uint64_t* out_request_id);
} ntkc_table;

/* Called by the Swift installer from inside the first ntk_* call (dispatch_once). */
void ntkc_register(const ntkc_table* table);
#endif
