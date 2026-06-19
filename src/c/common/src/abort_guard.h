#ifndef KE_ABORT_GUARD_H_
#define KE_ABORT_GUARD_H_

// Private implementation utility — NOT part of the public API.
// No KE_*_API exports, no bindings, no install.
//
// Provides a thread-local setjmp/longjmp guard for catching abort() calls
// issued by third-party backend libraries (flecs, enkiTS, etc.).
//
// Usage:
//   1. In your plugin's abort hook, call ke_abort_guard_longjmp() if a guard
//      is active; otherwise fall through to your fallback (_exit / log).
//   2. Wrap each vtable function that may trigger the backend's abort with:
//        KE_ABORT_GUARD("context string", fail_return_statement);
//        ... call backend ...
//        KE_ABORT_GUARD_END();
//
// The longjmp path records a ke_error in the TLS ring buffer (out_error=NULL)
// so callers can inspect ke_error_last() after a failed call.

#include <kernel_engine/common/error.h>

#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Thread-local state — one slot per thread; guards must not nest.
static _Thread_local char    ke__abort_msg[1024]  = {0};
static _Thread_local jmp_buf ke__abort_jmp;
static _Thread_local bool    ke__abort_active      = false;

// Returns the last message captured on this thread, or NULL.
// Valid until the next KE_ABORT_GUARD on this thread.
static inline const char *ke_abort_guard_last_message(void)
{
    return ke__abort_msg[0] ? ke__abort_msg : NULL;
}

// Record a message from the backend's log callback (call before abort fires).
static inline void ke_abort_guard_set_message(const char *file, int line, const char *msg)
{
    if (!msg) return;
    snprintf(ke__abort_msg, sizeof(ke__abort_msg),
             "%s:%d: %s", file ? file : "?", line, msg);
}

// Call from the backend's abort hook.
// Returns true if a guard was active (longjmp fired — caller must NOT continue).
// Returns false if no guard; caller should use its own fallback (_exit / log).
static inline bool ke_abort_guard_longjmp(void)
{
    if (!ke__abort_active) return false;
    ke__abort_active = false;
    longjmp(ke__abort_jmp, 1);
    // unreachable
    return true;
}

// KE_ABORT_GUARD(error_type, context_label, fail_return)
//   Arms the guard. If longjmp fires: records ke_error, executes fail_return.
//   MUST be paired with KE_ABORT_GUARD_END() on every normal exit path.
//
//   error_type   — pointer to a ke_error_type (plugin-specific domain type)
//   context_label — fallback message string if no log message was captured
//   fail_return  — statement(s) to execute on fatal (e.g. "return 0" or a block)
#define KE_ABORT_GUARD(error_type, context_label, fail_return)              \
    ke__abort_msg[0]  = '\0';                                               \
    ke__abort_active  = true;                                               \
    if (setjmp(ke__abort_jmp) != 0) {                                       \
        ke__abort_active = false;                                           \
        ke_error_set(NULL, (error_type),                                    \
            ke__abort_msg[0] ? ke__abort_msg : (context_label),            \
            __FILE__, __LINE__, NULL);                                      \
        fail_return;                                                        \
    }

#define KE_ABORT_GUARD_END() \
    ke__abort_active = false

#endif  // KE_ABORT_GUARD_H_
