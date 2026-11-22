/* Hand-off 2 smoke: the C part (no Objective-C). */
#ifndef HANDOFF2_SMOKE_SCENARIOS_H
#define HANDOFF2_SMOKE_SCENARIOS_H
/* Call from application:willFinishLaunchingWithOptions: (main thread). */
void smoke_install(void);
/* Call later; finished(failures) runs on the main thread. */
void smoke_run(void (*finished)(int failures));
#endif
