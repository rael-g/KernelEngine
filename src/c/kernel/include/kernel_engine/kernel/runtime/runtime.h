#ifndef KERNEL_ENGINE_KERNEL_RUNTIME_H_
#define KERNEL_ENGINE_KERNEL_RUNTIME_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// SPIKE: minimal subset of the ke_runtime contract from
// docs/RuntimeArchitectureV2.md §3. Exists to validate flecs builds in our
// stack and that the vtable shape is workable. Full surface (resources,
// extract phase, run-after/before deps, snapshot peek) lands in R2+.

typedef struct ke_runtime ke_runtime;

typedef uint64_t ke_module_id;
typedef uint64_t ke_system_id;

typedef enum ke_phase {
    KE_PHASE_STARTUP      = 0,
    KE_PHASE_PRE_UPDATE   = 1,
    KE_PHASE_FIXED_UPDATE = 2,
    KE_PHASE_UPDATE       = 3,
    KE_PHASE_POST_UPDATE  = 4,
    KE_PHASE_EXTRACT      = 5,
    KE_PHASE_SHUTDOWN     = 6,
} ke_phase;

typedef struct ke_module_params {
    const char *name;
    void       *user_data;
    ke_result (*on_load)(ke_runtime *runtime, void *user_data);
    void      (*on_unload)(ke_runtime *runtime, void *user_data);
} ke_module_params;

typedef struct ke_system_params {
    const char *name;
    ke_phase    phase;
    void       *user_data;
    void      (*execute)(ke_runtime *runtime, void *user_data, float dt);
} ke_system_params;

typedef struct ke_runtime {
    void *handle;

    ke_result (*register_module)(ke_runtime *self, const ke_module_params *p, ke_module_id *out_id);
    ke_result (*register_system)(ke_runtime *self, const ke_system_params *p, ke_system_id *out_id);

    ke_result (*tick)(ke_runtime *self, float dt);

    void (*destroy)(ke_runtime *self);
} ke_runtime;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RUNTIME_H_
