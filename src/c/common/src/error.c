#include "kernel_engine/common/error.h"
#include <kernel_engine/allocator/allocator.h>
#include <stdalign.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#endif

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

const ke_error* ke_error_last(void) {
    // s_slot was already advanced past the last write; the filled slot is 1-s_slot.
    int last = 1 - s_slot;
    return s_errors[last].type ? &s_errors[last] : NULL;
}

ke_error* ke_error_copy(const ke_error* src) {
    if (!src) return NULL;

    ke_error* copy = (ke_error*)ke_alloc(sizeof(ke_error), alignof(ke_error));
    if (!copy) return NULL;

    copy->type  = src->type;  // singleton, program lifetime
    copy->file  = src->file;  // __FILE__ literal, program lifetime
    copy->line  = src->line;
    copy->cause = NULL;

    if (src->message) {
        size_t n = strlen(src->message) + 1;
        char*  m = (char*)ke_alloc(n, 1);
        if (!m) { ke_free(copy); return NULL; }
        memcpy(m, src->message, n);
        copy->message = m;
    } else {
        copy->message = NULL;
    }

    if (src->cause) {
        ke_error* c = ke_error_copy(src->cause);
        if (!c) { ke_error_free(copy); return NULL; }
        copy->cause = c;
    }

    return copy;
}

void ke_error_free(ke_error* err) {
    while (err) {
        ke_error* cause = (ke_error*)err->cause;
        if (err->message) ke_free((void*)err->message);
        ke_free(err);
        err = cause;
    }
}

_Noreturn void ke_error_fatal(const ke_error* err) {
#if defined(_WIN32)
    // Kill every OS-level crash dialog (GPF/Watson, missing-DLL, file-open)
    // before the process goes down — this call is the reason ke_error_fatal
    // exits clean where abort()/__builtin_trap() would pop a modal dialog.
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
#endif

    fprintf(stderr, "FATAL: ");
    if (err) {
        const ke_error* e = err;
        while (e) {
            fprintf(stderr, "[%s] %s (%s:%u)", e->type ? e->type->name : "?",
                    e->message ? e->message : "(no message)",
                    e->file ? e->file : "?", e->line);
            e = e->cause;
            if (e) fprintf(stderr, "\n  caused by: ");
        }
        fprintf(stderr, "\n");
    } else {
        fprintf(stderr, "no error context provided\n");
    }
    fflush(stderr);

#if defined(_WIN32)
    ExitProcess(1);
#else
    _exit(1);
#endif
}
