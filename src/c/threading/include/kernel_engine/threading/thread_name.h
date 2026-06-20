#ifndef KERNEL_ENGINE_THREADING_THREAD_NAME_H_
#define KERNEL_ENGINE_THREADING_THREAD_NAME_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

void        ke_thread_set_current_name(const char *name);
const char *ke_thread_get_current_name(void);

/// Returns true if the calling thread's name matches expected_name.
/// On mismatch records a ke_error in the TLS ring and returns false.
/// Never calls assert() or abort().
bool ke_thread_check_current(const char *expected_name);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_THREADING_THREAD_NAME_H_
