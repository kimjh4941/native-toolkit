/* Internal to IosLibraryCApi (stage 1a prototype). Visible to the Swift code through the
   build-time module map next to this file; never copied into the framework. The names do not
   start with ntk_ so that the _ntk_* export list cannot pick them up. */
#ifndef NTKC_THREAD_LOCAL_H
#define NTKC_THREAD_LOCAL_H
#include <stdint.h>
uint32_t ntkc_tls_get(void);
void ntkc_tls_set(uint32_t value);
#endif
