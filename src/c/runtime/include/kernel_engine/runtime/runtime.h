#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_runtime    ke_runtime;
typedef struct ke_system_ctx ke_system_ctx;

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

typedef enum ke_access {
    KE_ACCESS_READ  = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
} ke_access;

typedef struct ke_component_access {
    ke_component_id cid;
    ke_access       access;
} ke_component_access;

typedef struct ke_runtime_module_params {
    const char *name;
    void       *user_data;
    ke_result (*on_load)(ke_runtime *runtime, void *user_data);
    void      (*on_unload)(ke_runtime *runtime, void *user_data);
} ke_runtime_module_params;

typedef struct ke_runtime_system_params {
    const char *name;
    ke_phase    phase;

    const ke_component_access *access_list;
    uint32_t                   access_count;

    bool     exclusive;
    uint32_t pinned_thread;

    void *user_data;
    void (*execute)(ke_system_ctx *ctx, void *user_data, float dt);
} ke_runtime_system_params;

typedef struct ke_runtime {
    void *handle;

    ke_result (*register_module)(ke_runtime *self, const ke_runtime_module_params *p, ke_module_id *out_id);
    ke_result (*register_system)(ke_runtime *self, const ke_runtime_system_params *p, ke_system_id *out_id);
    ke_result (*tick)(ke_runtime *self, float dt);
    void      (*destroy)(ke_runtime *self);
} ke_runtime;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RUNTIME_RUNTIME_H_
