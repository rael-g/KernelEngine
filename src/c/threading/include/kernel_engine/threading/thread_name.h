#ifndef KERNEL_ENGINE_THREADING_THREAD_NAME_H_
#define KERNEL_ENGINE_THREADING_THREAD_NAME_H_

#include <kernel_engine/common/export.h>

#ifdef __cplusplus
extern "C"
{
#endif

KE_API void        ke_thread_set_current_name(const char *name);
KE_API const char *ke_thread_get_current_name(void);
KE_API void        ke_thread_assert_current(const char *expected_name);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_THREADING_THREAD_NAME_H_
