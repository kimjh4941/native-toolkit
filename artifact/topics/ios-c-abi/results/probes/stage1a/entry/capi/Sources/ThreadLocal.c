/* C11 thread-local storage behind ntk_last_system_code (stage 1a prototype). */
#include "ThreadLocal.h"

static _Thread_local uint32_t ntkc_last_system_code;

uint32_t ntkc_tls_get(void) { return ntkc_last_system_code; }
void ntkc_tls_set(uint32_t value) { ntkc_last_system_code = value; }
