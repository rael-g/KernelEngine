#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps the scene graph's derived state in step with the hierarchy
    /// components, as ordinary runtime systems rather than a call the host has to
    /// remember to make.
    ///
    /// ke_hierarchy_component stores parenthood as an intrusive linked list
    /// (first_child / next_sibling), which is O(1) to relink but answers no
    /// question about the graph without walking it. Two systems close that gap:
    /// one flattens the list into an array ordered parents-before-children, the
    /// other walks that array once to turn local transforms into world matrices.
    /// Because the order is topological, the second never recurses — a parent's
    /// world matrix is always already final when its children are reached — so
    /// scene depth stops being bounded by the call stack.
    ///
    /// Both declare their component access, so the scheduler orders them against
    /// anything else touching transforms instead of trusting phase placement.
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
