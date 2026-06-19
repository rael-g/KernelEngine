#include <kernel_engine/threading/thread_name.h>
#include <kernel_engine/common/error.h>

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
   static _Thread_local const char *tls_thread_name = NULL;
#else
#  include <pthread.h>
   static _Thread_local const char *tls_thread_name = NULL;
#endif

void ke_thread_set_current_name(const char *name)
{
    tls_thread_name = name;
}

const char *ke_thread_get_current_name(void)
{
    return tls_thread_name;
}

ke_result ke_thread_check_current(const char *expected_name)
{
    const char *actual = tls_thread_name ? tls_thread_name : "(unnamed)";
    if (!tls_thread_name || strcmp(tls_thread_name, expected_name) != 0)
    {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "wrong thread: expected '%s', got '%s'", expected_name, actual);
        return ke_error_set(NULL, &KE_ERROR_INVALID_ARGUMENT, msg, __FILE__, __LINE__, NULL);
    }
    return KE_OK;
}
