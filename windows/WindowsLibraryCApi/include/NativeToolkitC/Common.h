/**
 * @file Common.h
 * @brief What every part of the NativeToolkit C ABI shares: the version, the
 *        last system code, and the three output handles (a string, bytes and
 *        a list of strings).
 *
 * Rules that hold for the whole C ABI (stage 5 design, sections 1 and 7):
 *  - Strings are NUL-terminated UTF-8, in and out.
 *  - Every handle a function hands out is released with its own _free, and
 *    _free(NULL) does nothing. Pointers read from a handle stay valid until
 *    that handle is freed.
 *  - A failing function reports its error as the return value; the raw value
 *    the OS gave, if any, is ntk_last_system_code() on the same thread.
 *  - The header is plain C99, includes nothing but <stddef.h> and <stdint.h>,
 *    and is ASCII only.
 */
#ifndef NATIVETOOLKITC_COMMON_H
#define NATIVETOOLKITC_COMMON_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define NTK_CALL __cdecl
#else
#define NTK_CALL
#endif

#define NTK_VERSION_MAJOR 2
#define NTK_VERSION_MINOR 0
#define NTK_VERSION_PATCH 0
/** (MAJOR << 16) | (MINOR << 8) | PATCH, written as a literal so that every binding generator can read it. */
#define NTK_VERSION 0x020000

/** ntk_last_system_code() after an out-of-memory failure the C ABI caught (E_OUTOFMEMORY). */
#define NTK_SYSTEM_CODE_E_OUTOFMEMORY 0x8007000E

/**
 * @brief Tells the caller that the library is done with a user_data pointer.
 * @details Called exactly once for every registration that takes one, whatever
 *          the registering function returned.
 */
typedef void (NTK_CALL *ntk_release_fn)(void* user_data);

/**
 * @brief The version of the DLL, in the form of NTK_VERSION.
 * @details Compare it with NTK_VERSION to find a header and a DLL that do not
 *          belong together.
 */
uint32_t NTK_CALL ntk_version(void);

/**
 * @brief The raw value the OS reported for the last failure on this thread.
 * @details Updated by every function that returns an error: 0 on success.
 *          Read it straight after the failure, on the same thread.
 */
uint32_t NTK_CALL ntk_last_system_code(void);

/** A string the library returned. */
typedef struct ntk_string ntk_string;
/** The text, NUL-terminated. Valid until the handle is freed. */
const char* NTK_CALL ntk_string_data(const ntk_string* s);
/** The length in bytes, without the terminator. */
size_t      NTK_CALL ntk_string_size(const ntk_string* s);
void        NTK_CALL ntk_string_free(ntk_string* s);

/** Bytes the library returned. */
typedef struct ntk_bytes ntk_bytes;
/** The bytes; never NULL for a valid handle, even when the size is 0. */
const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b);
size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);
void           NTK_CALL ntk_bytes_free(ntk_bytes* b);

/** A list of strings the library returned. */
typedef struct ntk_string_list ntk_string_list;
size_t      NTK_CALL ntk_string_list_count(const ntk_string_list* list);
/** The string at index, or NULL when index is out of range. out_size may be NULL. */
const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size);
void        NTK_CALL ntk_string_list_free(ntk_string_list* list);

#ifdef __cplusplus
}
#endif
#endif
