/* Stage 1a smoke: the C part (no Objective-C). */
#ifndef SMOKE_SCENARIOS_H
#define SMOKE_SCENARIOS_H
#include <stdint.h>
/* Runs the basic scenario; calls finished(failures) on the main thread when every request ended. */
void smoke_run_basic(void (*finished)(int failures));
/* Queues a UIKit exception through the C ABI. */
int32_t smoke_raise(int32_t kind);
#endif
