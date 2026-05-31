#ifndef KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/input/snapshot.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint64_t ke_entity;

    // ── Universal components (consumed by built-in native systems) ─────────
    // Domain-specific components (lighting, mesh, camera, skybox) live in the
    // language layer that owns the system that consumes them. The kernel only
    // declares components whose layout it relies on at the C level — i.e.,
    // components read or written by native systems (TransformSystem, ScriptSystem).

    // ── Transform ───────────────────────────────────────────────────────────

    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
        ke_mat4 world_matrix;
    } ke_transform_component;

    // ── Hierarchy ───────────────────────────────────────────────────────────

    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    // ── Name ────────────────────────────────────────────────────────────────

    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

    // ── Scripting ───────────────────────────────────────────────────────────

    typedef ke_result (*ke_script_func)(ke_entity entity);
    typedef ke_result (*ke_script_update_func)(ke_entity entity, float dt);
    typedef ke_result (*ke_script_input_func)(ke_entity entity, const ke_input_snapshot *input);

    // state values for ke_script_component.state
    #define KE_SCRIPT_STATE_FRESH   0  // not yet ticked
    #define KE_SCRIPT_STATE_AWOKE   1  // on_awake fired
    #define KE_SCRIPT_STATE_STARTED 2  // on_start fired; normal update loop

    typedef struct ke_script_component
    {
        uint8_t state;                    // KE_SCRIPT_STATE_*
        ke_script_func        on_awake;   // called once before on_start
        ke_script_func        on_start;   // called once before first on_update
        ke_script_update_func on_update;
        ke_script_update_func on_late_update; // called after all on_update in same frame
        ke_script_func        on_destroy; // called by ke_world_notify_destroy before ECS removal
        ke_script_input_func  on_input;   // called per frame when input snapshot is available
    } ke_script_component;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
