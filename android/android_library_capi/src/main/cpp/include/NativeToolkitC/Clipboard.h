/**
 * @file Clipboard.h
 * @brief The clipboard: copying, reading, the description of the clip and change events.
 *
 * Rules for the whole C ABI (C ABI design part 1, chapter 1): every function may be called from any
 * thread and never waits for the main thread; completions, events and accepted releases arrive on
 * the main thread; strings are NUL-terminated UTF-8; this header is C99, includes only <stddef.h>
 * and <stdint.h>, and is ASCII only. The declarations are those of Appendix A of the C ABI design
 * part 2, which scripts/check_c_abi_contract_android.py compares with this file.
 */
#ifndef NATIVETOOLKITC_CLIPBOARD_H
#define NATIVETOOLKITC_CLIPBOARD_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_clipboard_error;
enum {
    NTK_CLIPBOARD_ERROR_NONE = 0,
    NTK_CLIPBOARD_ERROR_INVALID_PARAMETER = 1,
    NTK_CLIPBOARD_ERROR_NOT_INITIALIZED = 2,
    NTK_CLIPBOARD_ERROR_NOT_SUPPORTED = 3,
    NTK_CLIPBOARD_ERROR_UNKNOWN = 4,
    NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY = 5,
    NTK_CLIPBOARD_ERROR_EMPTY_CONTENT = 6,
    NTK_CLIPBOARD_ERROR_EMPTY_ITEMS = 7,
    NTK_CLIPBOARD_ERROR_INVALID_URI = 8,
    NTK_CLIPBOARD_ERROR_UNAVAILABLE = 9,
    NTK_CLIPBOARD_ERROR_READ_NOT_ALLOWED = 10,
    NTK_CLIPBOARD_ERROR_SECURITY = 11
};

/** What ntk_clipboard_read returned. */
typedef struct ntk_clipboard_content ntk_clipboard_content;
/** What ntk_clipboard_get_description returned. */
typedef struct ntk_clipboard_description ntk_clipboard_description;
/** A change listener registration. */
typedef struct ntk_clipboard_listener ntk_clipboard_listener;

/** The clipboard changed. Called on the main thread. */
typedef void (NTK_CALL *ntk_clipboard_change_fn)(void* user_data);

#pragma pack(push, 8)
/** NULL means: no label, not sensitive. */
typedef struct ntk_clipboard_copy_options {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* label;            /**< NULL: no label. */
    int32_t     sensitive;        /**< Nonzero: mark the clip as sensitive. */
    uint32_t    reserved1;
} ntk_clipboard_copy_options;
#pragma pack(pop)

/* Writes, reads and queries run on the calling thread (AP-2). */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(const char* text, const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(const char* html, const char* plain_text,
                                                     const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_uri(const char* uri, const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_texts(const char* const* texts, size_t count,
                                                      const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);
/** *out_content is NULL when the clipboard is empty or the app has no input focus. */
ntk_clipboard_error NTK_CALL ntk_clipboard_read(ntk_clipboard_content** out_content);
ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int32_t* out_has_clip);
/** *out_description is NULL when the clipboard is empty. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_description(ntk_clipboard_description** out_description);

/* Posted to the main thread; NONE means accepted, not that observing started. Idempotent. */
ntk_clipboard_error NTK_CALL ntk_clipboard_start_observing(void);
ntk_clipboard_error NTK_CALL ntk_clipboard_stop_observing(void);

ntk_clipboard_error NTK_CALL ntk_clipboard_add_change_listener(ntk_clipboard_change_fn callback, void* user_data,
                                                               ntk_release_fn release,
                                                               ntk_clipboard_listener** out_listener);
/** Removes the registration. The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_clipboard_listener_remove(ntk_clipboard_listener* listener);

/* Readers: pointers stay valid until the handle is freed. out_size may be NULL. */
const char* NTK_CALL ntk_clipboard_content_label(const ntk_clipboard_content* content, size_t* out_size);
size_t      NTK_CALL ntk_clipboard_content_mime_type_count(const ntk_clipboard_content* content);
const char* NTK_CALL ntk_clipboard_content_mime_type_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
size_t      NTK_CALL ntk_clipboard_content_item_count(const ntk_clipboard_content* content);
const char* NTK_CALL ntk_clipboard_content_item_text_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_html_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_uri_at(const ntk_clipboard_content* content, size_t index,
                                                       size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_coerced_text_at(const ntk_clipboard_content* content, size_t index,
                                                                size_t* out_size);
void        NTK_CALL ntk_clipboard_content_free(ntk_clipboard_content* content);

const char* NTK_CALL ntk_clipboard_description_label(const ntk_clipboard_description* description,
                                                     size_t* out_size);
size_t      NTK_CALL ntk_clipboard_description_mime_type_count(const ntk_clipboard_description* description);
const char* NTK_CALL ntk_clipboard_description_mime_type_at(const ntk_clipboard_description* description,
                                                            size_t index, size_t* out_size);
int32_t     NTK_CALL ntk_clipboard_description_is_styled_text(const ntk_clipboard_description* description);
/** The classification status, or -1 when the OS did not report one. */
int32_t     NTK_CALL ntk_clipboard_description_classification_status(const ntk_clipboard_description* description);
void        NTK_CALL ntk_clipboard_description_free(ntk_clipboard_description* description);

#ifdef __cplusplus
}
#endif
#endif
