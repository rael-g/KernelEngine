#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps the scene graph's derived state in step with the hierarchy
    /// components, as runtime systems.
    ///
    /// One system flattens the child lists into an array ordered
    /// parents-before-children. The other walks that array once to turn local
    /// transforms into world matrices, so a parent's world matrix is final before
    /// its children are reached.
    ///
    /// Both declare their component access, so the scheduler orders them against
    /// other systems that touch transforms.
    typedef struct ke_scene_hierarchy ke_scene_hierarchy;

    /// Owner wrapper: destroy releases the flattening buffers. The systems are
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
