/* CT-01 of the stage 5 design, for Clipboard.h: included alone, compiled as C at /W4 /WX. */
#include "NativeToolkitC/Clipboard.h"

static ntk_clipboard_error NTK_CALL ntk_test_render(
    void* user_data, const char* format_name, ntk_clipboard_render_target* target)
{
    (void)user_data;
    (void)format_name;
    (void)target;
    return NTK_CLIPBOARD_ERROR_NONE;
}

size_t ntk_test_clipboard_header_compiles_as_c(void)
{
    ntk_clipboard_session_options options = {0};
    ntk_clipboard_history_handlers handlers = {0};
    ntk_clipboard_render_fn render = ntk_test_render;
    options.struct_size = (uint32_t)sizeof(options);
    handlers.struct_size = (uint32_t)sizeof(handlers);
    return options.struct_size + handlers.struct_size + (size_t)NTK_CLIPBOARD_WRITE_SENSITIVE +
           (render ? 1u : 0u);
}
