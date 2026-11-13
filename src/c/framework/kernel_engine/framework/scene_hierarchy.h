#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_

#include <kernel_engine/schedule/schedule.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps every world transform equal to its local transform composed with its
    /// parent's world transform, through one schedule system in the set its config names.
    ///
    /// Each tick the system orders the entities parents-before-children, then walks
    /// that order once, so a parent's world matrix is final before its children are
    /// reached.
    ///
    /// The system declares its component access, so the schedule orders it against
    /// other systems that touch transforms.
    typedef struct ke_scene_hierarchy ke_scene_hierarchy;

    /// [owner] Destroy unregisters the system and releases the ordering buffers.
    typedef struct ke_scene_hierarchy_handle
    {
        ke_scene_hierarchy *ref;
        void (*destroy)(ke_scene_hierarchy *self);
    } ke_scene_hierarchy_handle;

    /// [borrowed] The values the scene hierarchy is created with.
    typedef struct ke_scene_hierarchy_config
    {
        /// The set the propagation system joins; its schedule must run after transforms are written
        /// and before world transforms are read.
        ke_schedule_set_id set;
    } ke_scene_hierarchy_config;

#ifdef __cplusplus
}
#endif

#endif
