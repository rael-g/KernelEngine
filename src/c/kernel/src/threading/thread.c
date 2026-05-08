#include <kernel_engine/kernel/threading/thread.h>
#include <kernel_engine/kernel/context/types.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>

static KE_THREAD_LOCAL char s_thread_name[64] = "unknown";

void ke_thread_set_current_name(const char *name)
{
    if (name)
    {
        size_t i = 0;
        for (; i < sizeof(s_thread_name) - 1 && name[i] != '\0'; ++i)
        {
            s_thread_name[i] = name[i];
        }
        s_thread_name[i] = '\0';
    }
}

const char *ke_thread_get_current_name(void)
{
    return s_thread_name;
}

void ke_thread_assert_current(const char *expected_name)
{
#ifndef NDEBUG
    if (strcmp(s_thread_name, expected_name) != 0)
    {
        fprintf(stderr,
                "[FATAL] Thread affinity violation! Expected '%s', but current is '%s'.\n",
                expected_name, s_thread_name);
        assert(0);
        abort();
    }
#endif
}
