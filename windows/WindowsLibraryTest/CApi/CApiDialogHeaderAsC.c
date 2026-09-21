/* CT-01 of the stage 5 design, for Dialog.h: included alone, compiled as C at /W4 /WX. */
#include "NativeToolkitC/Dialog.h"

size_t ntk_test_dialog_header_compiles_as_c(void)
{
    ntk_dialog_filter filter = {0};
    ntk_dialog_alert_request alert = {0};
    alert.struct_size = (uint32_t)sizeof(alert);
    return sizeof(filter) + alert.struct_size + (size_t)NTK_DIALOG_ERROR_UNKNOWN;
}
