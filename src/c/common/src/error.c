#include "kernel_engine/common/error.h"
#include <string.h>

// Generic singletons
const ke_error_type KE_ERROR_GENERAL          = { "ke.error",                   NULL };
const ke_error_type KE_ERROR_NOT_FOUND        = { "ke.error.not_found",         NULL };
const ke_error_type KE_ERROR_IO               = { "ke.error.io",                NULL };
const ke_error_type KE_ERROR_OUT_OF_MEMORY    = { "ke.error.out_of_memory",     NULL };
const ke_error_type KE_ERROR_INVALID_ARGUMENT = { "ke.error.invalid_argument",  NULL };
const ke_error_type KE_ERROR_NOT_INITIALIZED  = { "ke.error.not_initialized",   NULL };
const ke_error_type KE_ERROR_NOT_SUPPORTED    = { "ke.error.not_supported",     NULL };
const ke_error_type KE_ERROR_ALREADY_EXISTS   = { "ke.error.already_exists",    NULL };

bool ke_error_is(const ke_error* err, const ke_error_type* type) {
    if (!err || !err->type || !type) return false;
    const ke_error_type* t = err->type;
    while (t) {
        if (t == type) return true;
        t = t->parent;
    }
    return false;
}

// Depth-2 ring buffer: two slots so that wrapping an error (KE_ERROR_WRAP) keeps
// the inner error pointer valid while the outer error is being constructed.
// Slots alternate: index 0 and 1; s_slot tracks which is filled next.
static _Thread_local ke_error s_errors[2];
static _Thread_local char     s_messages[2][512];
static _Thread_local int      s_slot = 0;

void ke_error_set(ke_error** out_error, const ke_error_type* type,
                  const char* message, const char* file, uint32_t line,
                  const ke_error* cause) {
    int slot = s_slot;
    s_slot   = 1 - slot;

    ke_error* e = &s_errors[slot];
    e->type  = type;
    e->file  = file;
    e->line  = line;
    e->cause = cause;
    if (message) {
        strncpy(s_messages[slot], message, sizeof(s_messages[slot]) - 1);
        s_messages[slot][sizeof(s_messages[slot]) - 1] = '\0';
    } else {
        s_messages[slot][0] = '\0';
    }
    e->message = s_messages[slot];
    if (out_error) *out_error = e;
}
