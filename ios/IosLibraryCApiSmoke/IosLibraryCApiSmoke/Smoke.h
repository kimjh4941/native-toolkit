/* The smoke of the iOS C ABI, its C part (C ABI design part 2, 12.4). */
#ifndef IOS_LIBRARY_CAPI_SMOKE_H
#define IOS_LIBRARY_CAPI_SMOKE_H

#include <stdint.h>

/* Called once on the main thread when every step ended; failures is 0 when all passed. */
typedef void (*smoke_finished_fn)(int failures);

/* Runs the steps on the main thread, one after another: the version, the notification delegate the
   host installed (install_result is what ntk_notification_install returned at launch), the
   clipboard (write and read a named pasteboard) and a dialog (shown, then cancelled, to its
   completion). Every step prints a "SMOKE PASS" or "SMOKE FAIL" line to stdout. */
void smoke_run(int32_t install_result, smoke_finished_fn finished);

#endif
