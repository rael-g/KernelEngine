#ifndef KERNEL_ENGINE_MODULE_MODULE_H_
#define KERNEL_ENGINE_MODULE_MODULE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/schedule/schedule.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_module ke_module;

/// [bag] The standard schedules of a world and their sets, which a module attaches its systems to.
typedef struct ke_module_targets {
    /// Runs once, before the first tick's other schedules.
    ke_schedule *startup;
    /// Runs first in every tick.
    ke_schedule *pre_update;
    /// Runs once per fixed step.
    ke_schedule *fixed;
    /// Runs after the fixed steps in every tick.
    ke_schedule *update;
    /// Runs once, when the loop shuts down.
    ke_schedule *shutdown;
    /// Runs over the render world once per extraction; NULL where there is none.
    ke_schedule *render;
    /// In startup.
    ke_schedule_set_id startup_set;
    /// In pre_update.
    ke_schedule_set_id pre_update_set;
    /// In fixed, first.
    ke_schedule_set_id fixed_pre_update_set;
    /// In fixed, after fixed_pre_update_set.
    ke_schedule_set_id fixed_update_set;
    /// In fixed, after fixed_update_set.
    ke_schedule_set_id fixed_post_update_set;
    /// In update, first.
    ke_schedule_set_id update_set;
    /// In update, after update_set.
    ke_schedule_set_id post_update_set;
    /// In shutdown.
    ke_schedule_set_id shutdown_set;
    /// In render, first: where the frame begins.
    ke_schedule_set_id render_begin_set;
    /// In render, after render_begin_set: where uploads run and passes make what they hand to others.
    ke_schedule_set_id render_prepare_set;
    /// In render, after render_prepare_set: where passes are declared.
    ke_schedule_set_id render_queue_set;
    /// In render, after render_queue_set: where the frame is executed and presented.
    ke_schedule_set_id render_submit_set;
} ke_module_targets;

/// [interface] A piece that fits into a world by registering its systems in the standard schedules.
typedef struct ke_module {
    void *handle;

    /// Registers the module's systems in @p targets, whose schedules must outlive the attachment.
    /// @param targets [borrowed] Read during the call.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null @p targets or a null schedule the module
    ///         uses; KE_RESULT_NOT_SUPPORTED when the module is already attached; the code a
    ///         schedule refused a system with, nothing left registered.
    ke_result (*attach)(ke_module *self, const ke_module_targets *targets);

    /// Removes exactly what attach registered, and nothing else: components and entities stay in
    /// the world. A module not attached is left alone.
    void (*detach)(ke_module *self);
} ke_module;

/// [owner]
typedef struct ke_module_handle {
    ke_module *ref;
    void (*destroy)(ke_module *self);
} ke_module_handle;

#ifdef __cplusplus
}
#endif

#endif
