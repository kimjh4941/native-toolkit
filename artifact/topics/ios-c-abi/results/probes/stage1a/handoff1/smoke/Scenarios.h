/* Hand-off 1 smoke: the C part (no Objective-C). */
#ifndef HANDOFF1_SMOKE_SCENARIOS_H
#define HANDOFF1_SMOKE_SCENARIOS_H
/* set_window_hidden(1) hides the key window (not in the foreground), (0) shows it again. */
void smoke_run(void (*set_window_hidden)(int hidden), void (*finished)(int failures));
#endif
