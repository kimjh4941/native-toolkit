/**
 * @file Notification.h
 * @brief Toast notifications: the runtime, the manager, its operations, and
 *        the content builder (OP-07..OP-20).
 *
 * Threads: every function may be called from any thread. The operations that
 * wait for the OS block the calling thread until it answers.
 *
 * Activations arrive on a thread the OS picks, never on a thread of yours by
 * arrangement. The one exception is the activation that launched the process
 * (cold start): it arrives inside ntk_notification_manager_create, on the
 * calling thread, before *out_manager is written.
 *
 * One manager per process: Windows registers one activation handler per
 * process, so a second ntk_notification_manager_create is refused with
 * NTK_NOTIFICATION_ERROR_NOT_SUPPORTED until the first is closed.
 *
 * COM: ntk_notification_manager_create initialises the calling thread for COM
 * as an MTA and does not uninitialise it. A thread that is to own a clipboard
 * session must not be that thread (design 1.3.3).
 */
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

/** The result of every notification function that can fail. */
typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 1,     /**< The manager is closed. */
    NTK_NOTIFICATION_ERROR_DISABLED = 2,            /**< Notifications are off for this app or user. */
    NTK_NOTIFICATION_ERROR_INVALID_PAYLOAD = 3,     /* reserved, never returned */
    NTK_NOTIFICATION_ERROR_PROGRESS_NOT_FOUND = 4,  /**< No notification to update, or a stale sequence number. */
    NTK_NOTIFICATION_ERROR_HRESULT_FAILURE = 5,     /**< The OS failed; see ntk_last_system_code(). */
    NTK_NOTIFICATION_ERROR_BADGE_FAILED = 6,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 7,   /**< A NULL handle or output, malformed input, or content the OS would refuse. */
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 8        /**< Not available for this app type, a second manager or runtime, or an input struct from a newer version. */
};

typedef int32_t ntk_notification_setting;
enum {
    NTK_NOTIFICATION_SETTING_ENABLED = 0,
    NTK_NOTIFICATION_SETTING_DISABLED_FOR_APPLICATION = 1,
    NTK_NOTIFICATION_SETTING_DISABLED_FOR_USER = 2,
    NTK_NOTIFICATION_SETTING_DISABLED_BY_GROUP_POLICY = 3,
    NTK_NOTIFICATION_SETTING_DISABLED_BY_MANIFEST = 4
};

typedef int32_t ntk_notification_scenario;
enum {
    NTK_NOTIFICATION_SCENARIO_DEFAULT = 0,
    NTK_NOTIFICATION_SCENARIO_REMINDER = 1,
    NTK_NOTIFICATION_SCENARIO_ALARM = 2,
    NTK_NOTIFICATION_SCENARIO_URGENT = 3,
    NTK_NOTIFICATION_SCENARIO_INCOMING_CALL = 4
};

typedef int32_t ntk_notification_audio_kind;
enum {
    NTK_NOTIFICATION_AUDIO_KIND_EVENT = 0,   /**< A named system sound. */
    NTK_NOTIFICATION_AUDIO_KIND_MUTE = 1,    /**< No sound; the loop and event name are ignored. */
    NTK_NOTIFICATION_AUDIO_KIND_URI = 2      /**< The sound at the given URI. */
};

typedef int32_t ntk_notification_duration;
enum {
    NTK_NOTIFICATION_DURATION_SHORT = 0,
    NTK_NOTIFICATION_DURATION_LONG = 1       /**< Required before a looping sound is allowed. */
};

typedef int32_t ntk_notification_logo_crop;
enum {
    NTK_NOTIFICATION_LOGO_CROP_NONE = 0,
    NTK_NOTIFICATION_LOGO_CROP_CIRCLE = 1
};

/** The Windows App SDK runtime, loaded for an unpackaged app. */
typedef struct ntk_notification_runtime ntk_notification_runtime;
/** The one notification manager of the process. */
typedef struct ntk_notification_manager ntk_notification_manager;
/** A notification being described. Not thread safe: build it on one thread. */
typedef struct ntk_notification_content ntk_notification_content;
/** The output of ntk_notification_get_all. */
typedef struct ntk_notification_list ntk_notification_list;
/** What a user's click carried. Lent to ntk_notification_invoked_fn for the call only. */
typedef struct ntk_notification_activation ntk_notification_activation;

/**
 * @brief Receives an activation: the user clicked the notification, a button,
 *        or submitted its inputs.
 * @details Runs on a thread the OS picks. The activation and every pointer
 *          read from it are valid only during the call. Do not close, free or
 *          replace the handler of the manager from inside it, and do not
 *          block waiting for another thread that might be doing so.
 */
typedef void (NTK_CALL *ntk_notification_invoked_fn)(
    void* user_data, const ntk_notification_activation* activation);

/** How to create the manager. sizeof 56. */
typedef struct ntk_notification_manager_options {
    uint32_t                    struct_size;
    uint32_t                    reserved0;           /**< Must be 0. */
    ntk_notification_invoked_fn on_invoked;          /**< NULL: activations are dropped. */
    void*                       user_data;           /**< Passed to on_invoked and release. */
    ntk_release_fn              release;             /**< May be NULL. Called once when the library is done with user_data. */
    int32_t                     is_unpackaged;       /**< Non-zero for an app without package identity. */
    uint32_t                    reserved1;           /**< Must be 0. */
    const char*                 display_name;        /**< Required when is_unpackaged. NULL is "". */
    const char*                 icon_uri;            /**< Required when is_unpackaged. NULL is "". */
} ntk_notification_manager_options;

/** A new state for a notification that shows progress. sizeof 56. */
typedef struct ntk_notification_progress_update {
    uint32_t    struct_size;
    uint32_t    reserved0;                           /**< Must be 0. */
    const char* tag;                                 /**< NULL is "". */
    const char* group;                               /**< NULL is "". */
    double      value;                               /**< 0.0 to 1.0. */
    const char* value_string;                        /**< NULL is "". */
    const char* status;                              /**< NULL is "". */
    uint32_t    sequence_number;                     /**< Yours to increase; the OS drops stale ones. */
    uint32_t    reserved1;                           /**< Must be 0. */
} ntk_notification_progress_update;

/* ------------------------------------------------------------------------ */
/* Runtime (unpackaged apps only)                                           */
/* ------------------------------------------------------------------------ */

/**
 * @brief OP-07. Loads the Windows App SDK runtime for an app without package
 *        identity. Call it before ntk_notification_manager_create.
 * @param major_minor The runtime version, e.g. 0x00010007 for 1.7.
 * @details One runtime per process: a second call while the first handle is
 *          alive, or while its release is still waiting for the managers to
 *          close, is NTK_NOTIFICATION_ERROR_NOT_SUPPORTED.
 * @retval NTK_NOTIFICATION_ERROR_INVALID_PARAMETER out_runtime is NULL.
 * @retval NTK_NOTIFICATION_ERROR_NOT_SUPPORTED     A runtime is already loaded.
 * @retval NTK_NOTIFICATION_ERROR_HRESULT_FAILURE   The bootstrap failed; see ntk_last_system_code().
 */
ntk_notification_error NTK_CALL ntk_notification_runtime_initialize(
    uint32_t major_minor, ntk_notification_runtime** out_runtime);

/**
 * @brief Releases the runtime. The runtime is unloaded now if no manager is
 *        open, otherwise when the last manager closes.
 */
void NTK_CALL ntk_notification_runtime_free(ntk_notification_runtime* runtime);

/* ------------------------------------------------------------------------ */
/* Manager                                                                  */
/* ------------------------------------------------------------------------ */

/**
 * @brief OP-08. Registers this process for notifications and creates the manager.
 * @details options->release is called exactly once whatever this returns: on
 *          failure, on the calling thread before this returns; on success,
 *          once the handler has been replaced or the manager closed and the
 *          last activation in flight has returned. It is not called only when
 *          it cannot be read: options is NULL, or its struct_size is below the
 *          size of this version or above 4096.
 * @retval NTK_NOTIFICATION_ERROR_INVALID_PARAMETER A NULL argument, malformed options, or a missing name or icon for an unpackaged app.
 * @retval NTK_NOTIFICATION_ERROR_NOT_SUPPORTED     A manager is already open, or options come from a newer version.
 * @retval NTK_NOTIFICATION_ERROR_HRESULT_FAILURE   Registration failed; see ntk_last_system_code().
 */
ntk_notification_error NTK_CALL ntk_notification_manager_create(
    const ntk_notification_manager_options* options, ntk_notification_manager** out_manager);

/**
 * @brief Replaces the activation handler. on_invoked may be NULL to drop activations.
 * @details release is called exactly once whatever this returns. The previous
 *          handler's release follows once no activation is running it; an
 *          activation already in flight may still run the previous handler
 *          after this returns.
 * @retval NTK_NOTIFICATION_ERROR_INVALID_PARAMETER manager is NULL.
 * @retval NTK_NOTIFICATION_ERROR_NOT_INITIALIZED   The manager is closed; nothing is registered.
 */
ntk_notification_error NTK_CALL ntk_notification_manager_set_invoked_handler(
    ntk_notification_manager* manager, ntk_notification_invoked_fn on_invoked, void* user_data,
    ntk_release_fn release);

/**
 * @brief OP-09. Unregisters the process. Every operation then returns
 *        NTK_NOTIFICATION_ERROR_NOT_INITIALIZED. Closing twice does nothing.
 * @details An activation already in flight may still run once after this
 *          returns; the handler's release comes after it.
 */
void NTK_CALL ntk_notification_manager_close(ntk_notification_manager* manager);

/** @brief Closes the manager if it is open, then frees the handle. */
void NTK_CALL ntk_notification_manager_free(ntk_notification_manager* manager);

/* ------------------------------------------------------------------------ */
/* Operations. Each returns NTK_NOTIFICATION_ERROR_INVALID_PARAMETER for a   */
/* NULL manager or output, and NTK_NOTIFICATION_ERROR_NOT_INITIALIZED once   */
/* the manager is closed.                                                   */
/* ------------------------------------------------------------------------ */

/** @brief OP-10. Shows a notification now. The content is not changed and may be reused. */
ntk_notification_error NTK_CALL ntk_notification_show(
    ntk_notification_manager* manager, const ntk_notification_content* content);

/**
 * @brief OP-11. Shows a notification at unix_ms (milliseconds since 1970-01-01 UTC).
 *        Progress is ignored. A time beyond about 29,000 years either side is
 *        NTK_NOTIFICATION_ERROR_INVALID_PARAMETER.
 */
ntk_notification_error NTK_CALL ntk_notification_schedule(
    ntk_notification_manager* manager, const ntk_notification_content* content, int64_t unix_ms);

/** @brief OP-12. Cancels scheduled notifications with this tag and group. NULL is "". */
ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(
    ntk_notification_manager* manager, const char* tag, const char* group);

/**
 * @brief OP-13. Updates the progress of a shown notification.
 * @retval NTK_NOTIFICATION_ERROR_PROGRESS_NOT_FOUND No such notification, or a stale sequence number.
 * @retval NTK_NOTIFICATION_ERROR_NOT_SUPPORTED      update comes from a newer version.
 */
ntk_notification_error NTK_CALL ntk_notification_update_progress(
    ntk_notification_manager* manager, const ntk_notification_progress_update* update);

/** @brief OP-14. Sets the badge on the taskbar icon: a count, or a glyph for -1 to -6. */
ntk_notification_error NTK_CALL ntk_notification_set_badge(
    ntk_notification_manager* manager, int32_t value);

/** @brief OP-15. Removes the notification with this id from the action centre. */
ntk_notification_error NTK_CALL ntk_notification_remove_by_id(
    ntk_notification_manager* manager, uint32_t id);

/** @brief OP-16. Removes the notifications with this tag and group. NULL is "". */
ntk_notification_error NTK_CALL ntk_notification_remove_by_tag(
    ntk_notification_manager* manager, const char* tag, const char* group);

/** @brief OP-17. Removes every notification of this app. */
ntk_notification_error NTK_CALL ntk_notification_remove_all(ntk_notification_manager* manager);

/**
 * @brief OP-18. Lists the notifications of this app in the action centre.
 * @param out_list Receives a handle to free with ntk_notification_list_free; NULL on failure.
 */
ntk_notification_error NTK_CALL ntk_notification_get_all(
    ntk_notification_manager* manager, ntk_notification_list** out_list);

/** @brief OP-19. Whether the user or the system lets this app show notifications. */
ntk_notification_error NTK_CALL ntk_notification_get_setting(
    ntk_notification_manager* manager, ntk_notification_setting* out_setting);

/** @brief OP-20. Opens the notification page of the Settings app. */
ntk_notification_error NTK_CALL ntk_notification_open_settings(ntk_notification_manager* manager);

/* ------------------------------------------------------------------------ */
/* List (output of ntk_notification_get_all). NULL or an index out of range */
/* reads as 0 or NULL: check the count first.                               */
/* ------------------------------------------------------------------------ */

size_t      NTK_CALL ntk_notification_list_count(const ntk_notification_list* list);
uint32_t    NTK_CALL ntk_notification_list_id_at(const ntk_notification_list* list, size_t index);
const char* NTK_CALL ntk_notification_list_tag_at(
    const ntk_notification_list* list, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_list_group_at(
    const ntk_notification_list* list, size_t index, size_t* out_size);
void        NTK_CALL ntk_notification_list_free(ntk_notification_list* list);

/* ------------------------------------------------------------------------ */
/* Activation (argument of ntk_notification_invoked_fn). Valid during the   */
/* call only.                                                               */
/* ------------------------------------------------------------------------ */

/** The arguments as the library received them, as JSON: the same text the 1.x C ABI passed. */
const char* NTK_CALL ntk_notification_activation_raw_arguments(
    const ntk_notification_activation* activation, size_t* out_size);
/** The number of key and value pairs (button arguments and the user's input), in no particular order. */
size_t      NTK_CALL ntk_notification_activation_value_count(
    const ntk_notification_activation* activation);
const char* NTK_CALL ntk_notification_activation_key_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_activation_value_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size);

/* ------------------------------------------------------------------------ */
/* Content builder. Every setter returns NTK_NOTIFICATION_ERROR_INVALID_    */
/* PARAMETER for a NULL content, invalid UTF-8, an index or enum value out  */
/* of range, or a required string that is NULL. The builder checks nothing */
/* else: ntk_notification_show refuses content the OS would.               */
/* For the optional strings, NULL means absent and "" means present and    */
/* empty.                                                                   */
/* ------------------------------------------------------------------------ */

ntk_notification_error NTK_CALL ntk_notification_content_create(ntk_notification_content** out_content);
void NTK_CALL ntk_notification_content_free(ntk_notification_content* content);
/** Optional: NULL removes it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_title(ntk_notification_content* content, const char* value);
/** Optional: NULL removes it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_body(ntk_notification_content* content, const char* value);
/** NULL is "". */
ntk_notification_error NTK_CALL ntk_notification_content_set_tag(ntk_notification_content* content, const char* value);
/** NULL is "". */
ntk_notification_error NTK_CALL ntk_notification_content_set_group(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_scenario(
    ntk_notification_content* content, ntk_notification_scenario value);
/** Optional: NULL removes it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_hero_image(ntk_notification_content* content, const char* value);
/** Optional: NULL removes it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_inline_image(ntk_notification_content* content, const char* value);
/** uri NULL removes the logo. */
ntk_notification_error NTK_CALL ntk_notification_content_set_app_logo(
    ntk_notification_content* content, const char* uri, ntk_notification_logo_crop crop);
/** Optional: NULL removes it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_attribution(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_duration(
    ntk_notification_content* content, ntk_notification_duration value);
/** event_name NULL is ""; uri NULL is absent. A looping sound needs NTK_NOTIFICATION_DURATION_LONG. */
ntk_notification_error NTK_CALL ntk_notification_content_set_audio(
    ntk_notification_content* content, ntk_notification_audio_kind kind, const char* event_name,
    const char* uri, int32_t loop);
/**
 * Adds a button (at most five are shown). label is required; invoke_uri NULL
 * is absent. with_arguments non-zero gives the button an empty argument list
 * to add to. out_index may be NULL.
 */
ntk_notification_error NTK_CALL ntk_notification_content_add_button(
    ntk_notification_content* content, const char* label, const char* invoke_uri,
    int32_t with_arguments, size_t* out_index);
/** key is required; value NULL is "". Gives the button an argument list if it had none. */
ntk_notification_error NTK_CALL ntk_notification_content_add_button_argument(
    ntk_notification_content* content, size_t button_index, const char* key, const char* value);
/** id is required; placeholder and title NULL are absent. */
ntk_notification_error NTK_CALL ntk_notification_content_add_text_input(
    ntk_notification_content* content, const char* id, const char* placeholder, const char* title);
/** id is required; title and default_selection NULL are "". out_index may be NULL. */
ntk_notification_error NTK_CALL ntk_notification_content_add_combo(
    ntk_notification_content* content, const char* id, const char* title,
    const char* default_selection, size_t* out_index);
/** id and label are required. */
ntk_notification_error NTK_CALL ntk_notification_content_add_combo_item(
    ntk_notification_content* content, size_t combo_index, const char* id, const char* label);
/** Each string NULL is absent. Ignored when scheduling. */
ntk_notification_error NTK_CALL ntk_notification_content_set_progress(
    ntk_notification_content* content, const char* title, double value,
    const char* value_string, const char* status);
/**
 * The time the notification claims, in milliseconds since 1970-01-01 UTC.
 * Beyond about 29,000 years either side is NTK_NOTIFICATION_ERROR_INVALID_PARAMETER.
 */
ntk_notification_error NTK_CALL ntk_notification_content_set_timestamp(
    ntk_notification_content* content, int64_t unix_ms);
/** Seconds after delivery at which the action centre drops it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_expiration(
    ntk_notification_content* content, int64_t seconds);
/** Non-zero: dropped at the next reboot. Packaged apps only. */
ntk_notification_error NTK_CALL ntk_notification_content_set_expires_on_reboot(
    ntk_notification_content* content, int32_t value);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
