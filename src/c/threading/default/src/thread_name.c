#include <kernel_engine/threading/thread_name.h>

#include <assert.h>
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

void ke_thread_assert_current(const char *expected_name)
{
    const char *actual = tls_thread_name;
    assert(actual && strcmp(actual, expected_name) == 0 &&
           "ke_thread_assert_current: called from wrong thread");
    (void)actual;
    (void)expected_name;
}
