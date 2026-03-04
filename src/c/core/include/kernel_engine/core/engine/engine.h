#ifndef KERNEL_ENGINE_CORE_ENGINE_ENGINE_H_
#define KERNEL_ENGINE_CORE_ENGINE_ENGINE_H_

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <kernel_engine/core/engine/frame.h>
#include <kernel_engine/core/engine/system.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_ENGINE "ke_engine"

    /// @brief Central engine controller responsible for system orchestration.
    typedef struct ke_engine
    {
        void *handle;

        struct ke_allocator *allocator;
        struct ke_logger *logger;

        void (*destroy)(struct ke_engine *self);
        ke_result (*initialize)(struct ke_engine *self);
        ke_result (*tick)(struct ke_engine *self, const struct ke_frame *frame);
        ke_result (*shutdown)(struct ke_engine *self);

        ke_result (*register_system)(struct ke_engine *self, struct ke_system *system);

    } ke_engine;

    /// @brief Creates the kernel engine instance.
    KE_API ke_result ke_engine_create(const ke_descriptor *desc, ke_engine **out_engine);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_ENGINE_ENGINE_H_
