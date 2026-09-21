/* CT-01 of the stage 5 design, for Notification.h: included alone, compiled as C at /W4 /WX. */
#include "NativeToolkitC/Notification.h"

static void NTK_CALL ntk_test_on_invoked(void* user_data, const ntk_notification_activation* activation)
{
    (void)user_data;
    (void)ntk_notification_activation_value_count(activation);
}

size_t ntk_test_notification_header_compiles_as_c(void)
{
    ntk_notification_manager_options options = {0};
    ntk_notification_progress_update update = {0};
    options.struct_size = (uint32_t)sizeof(options);
    options.on_invoked = ntk_test_on_invoked;
    update.struct_size = (uint32_t)sizeof(update);
    return options.struct_size + update.struct_size + (size_t)NTK_NOTIFICATION_ERROR_NOT_SUPPORTED;
}
