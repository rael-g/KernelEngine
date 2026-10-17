#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps every world transform equal to its local transform composed with its
    /// parent's world transform, through one runtime system in the post-update phase.
    ///
    /// Each tick the system orders the entities parents-before-children, then walks
    /// that order once, so a parent's world matrix is final before its children are
    /// reached.
    ///
    /// The system declares its component access, so the scheduler orders it against
    /// other systems that touch transforms.
    typedef struct ke_scene_hierarchy ke_scene_hierarchy;

    /// Owner wrapper: destroy releases the ordering buffers. The system is
    /// registered for the runtime's lifetime, so destroy the hierarchy only once
    /// the runtime it was created against is done ticking.
    typedef struct ke_scene_hierarchy_handle
    {
        ke_scene_hierarchy *ref;
        void (*destroy)(ke_scene_hierarchy *self);
    } ke_scene_hierarchy_handle;

#ifdef __cplusplus
}
#endif

#endif
