// CT-04 of the stage 5 design: the input structs are laid out exactly as
// Appendix A says, on x64, and a caller's #pragma pack does not change that
// (the headers push pack 8 around their structs).
//
// Everything here is a static_assert, so a wrong layout fails the build. The
// headers are included under #pragma pack(1) on purpose; without their own
// push/pop the offsets below would come out packed.
//
// No precompiled header, so that the pack in force at the includes is the one
// written here.

#pragma pack(push, 1)
#include "NativeToolkitC/Dialog.h"
#pragma pack(pop)

#include <cstddef>

#define NTK_LAYOUT(type, member, offset) \
    static_assert(offsetof(type, member) == (offset), #type "." #member " moved")

static_assert(sizeof(ntk_dialog_filter) == 16, "ntk_dialog_filter");
NTK_LAYOUT(ntk_dialog_filter, name, 0);
NTK_LAYOUT(ntk_dialog_filter, patterns, 8);

static_assert(sizeof(ntk_dialog_alert_request) == 56, "ntk_dialog_alert_request");
NTK_LAYOUT(ntk_dialog_alert_request, struct_size, 0);
NTK_LAYOUT(ntk_dialog_alert_request, reserved0, 4);
NTK_LAYOUT(ntk_dialog_alert_request, title, 8);
NTK_LAYOUT(ntk_dialog_alert_request, message, 16);
NTK_LAYOUT(ntk_dialog_alert_request, buttons, 24);
NTK_LAYOUT(ntk_dialog_alert_request, icon, 28);
NTK_LAYOUT(ntk_dialog_alert_request, default_button, 32);
NTK_LAYOUT(ntk_dialog_alert_request, top_most, 36);
NTK_LAYOUT(ntk_dialog_alert_request, show_help_button, 40);
NTK_LAYOUT(ntk_dialog_alert_request, reserved1, 44);
NTK_LAYOUT(ntk_dialog_alert_request, owner, 48);

static_assert(sizeof(ntk_dialog_file_request) == 32, "ntk_dialog_file_request");
NTK_LAYOUT(ntk_dialog_file_request, title, 8);
NTK_LAYOUT(ntk_dialog_file_request, allow_missing_file, 16);
NTK_LAYOUT(ntk_dialog_file_request, reserved1, 20);
NTK_LAYOUT(ntk_dialog_file_request, owner, 24);

static_assert(sizeof(ntk_dialog_save_file_request) == 40, "ntk_dialog_save_file_request");
NTK_LAYOUT(ntk_dialog_save_file_request, title, 8);
NTK_LAYOUT(ntk_dialog_save_file_request, default_extension, 16);
NTK_LAYOUT(ntk_dialog_save_file_request, skip_overwrite_prompt, 24);
NTK_LAYOUT(ntk_dialog_save_file_request, reserved1, 28);
NTK_LAYOUT(ntk_dialog_save_file_request, owner, 32);

static_assert(sizeof(ntk_dialog_folder_request) == 24, "ntk_dialog_folder_request");
NTK_LAYOUT(ntk_dialog_folder_request, title, 8);
NTK_LAYOUT(ntk_dialog_folder_request, owner, 16);

// Anything to link.
extern "C" int ntk_test_layout() { return 0; }
