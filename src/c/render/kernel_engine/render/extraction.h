#ifndef KERNEL_ENGINE_RENDER_EXTRACTION_H_
#define KERNEL_ENGINE_RENDER_EXTRACTION_H_

#include <kernel_engine/tasks/completion.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The tag a main-world entity carries to have a pair in the render world.
#define KE_COMPONENT_NAME_RENDER_SYNCED "extraction.render_synced"
/// The tag a main-world entity carries to have its interpolated components blended between steps.
#define KE_COMPONENT_NAME_INTERPOLATED "extraction.interpolated"
/// The tag a main-world entity carries for one extraction to skip blending, its previous value taken from
/// its current one; the extraction removes it.
#define KE_COMPONENT_NAME_TELEPORTED "extraction.teleported"
/// The tag a render-world entity carries to be destroyed at the start of the next extraction.
#define KE_COMPONENT_NAME_FRAME_LOCAL "extraction.frame_local"

typedef struct ke_extraction ke_extraction;

/// Blends one component between two fixed steps.
/// @param user [context] Forwarded from extract_interpolate.
/// @param previous [borrowed] The value at the last fixed step but one.
/// @param current [borrowed] The value at the last fixed step.
/// @param alpha How far the time is between the two, in [0, 1).
/// @param out [out] Receives the render world's value, as large as the render component.
typedef void (*ke_extraction_interpolate_fn)(void *user, const void *previous, const void *current, float alpha, void *out);

/// Extracts what a copy cannot: reads the main world and writes the render world.
/// @param user [context] Forwarded from extract_custom.
/// @param main [borrowed] The main world, read only, while nothing else touches it.
/// @param render [borrowed] The render world.
/// @return KE_OK, or the code the extraction fails with.
typedef ke_result (*ke_extraction_custom_fn)(void *user, ke_extraction *extraction, ke_ecs *main, ke_ecs *render);

/// [interface] Gives every main-world entity tagged render_synced, or carrying a component registered with
/// sync_component, a pair in the render world, and makes the
/// registered components of each pair what they are in the main world at the moment of an extraction.
typedef struct ke_extraction {
    void *handle;

    /// Pairs every main-world entity carrying @p main_component as if it were tagged render_synced; the
    /// pair goes when the entity loses the component and the tag. Registering it again changes nothing.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown component; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*sync_component)(ke_extraction *self, ke_component_id main_component);

    /// Registers a copy: at each extraction, the pair carries @p render_component equal to the entity's
    /// @p main_component, every ENTITY field holding the entity's pair or the null entity; when the entity
    /// lost the component, the pair loses it too. Both must have the same size; registering the same
    /// pair again changes nothing.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown component or different sizes;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*extract_copy)(ke_extraction *self, ke_component_id main_component, ke_component_id render_component);

    /// Registers an interpolation: like a copy, except that for an entity tagged interpolated the pair
    /// receives @p blend of @p previous_component and @p main_component at the loop's alpha. An entity first
    /// paired, or tagged teleported, takes its current value as its previous one.
    /// @param blend [closure:user] Blends the two values.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown component, a null @p blend or sizes that
    ///         differ; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*extract_interpolate)(ke_extraction *self, ke_component_id main_component, ke_component_id previous_component,
                                     ke_component_id render_component, ke_extraction_interpolate_fn blend, void *user);

    /// Registers @p extract, run at each extraction after the copies, in the order registered.
    /// @param extract [closure:user] What it runs.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p extract; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*extract_custom)(ke_extraction *self, ke_extraction_custom_fn extract, void *user);

    /// The render-world pair of @p main.
    /// @param out_entity [out] Receives the pair; the null entity on failure.
    /// @return KE_OK; KE_RESULT_NOT_FOUND when @p main has no pair.
    ke_result (*render_entity)(ke_extraction *self, ke_entity main, ke_entity *out_entity);

    /// The main-world entity whose pair is @p render.
    /// @param out_entity [out] Receives the entity; the null entity on failure.
    /// @return KE_OK; KE_RESULT_NOT_FOUND when @p render is no pair.
    ke_result (*main_entity)(ke_extraction *self, ke_entity render, ke_entity *out_entity);

    /// Extracts, on the calling thread, with neither world touched by anything else: destroys the render
    /// world's frame_local entities, pairs the newly synced entities and drops the pairs of the others, then
    /// runs the copies, the interpolations at @p alpha and the custom extractions.
    /// @return KE_OK, or the code of the world or the extraction that failed.
    ke_result (*extract)(ke_extraction *self, float alpha);

    /// One extraction, with the ABI of a scheduler's executable whose user is the extraction: extracts at the
    /// scheduler's fixed alpha. What runs over the render world is added to the scheduler after it.
    /// @param out_completion [out] Receives a completion already finished with KE_OK, which the caller releases.
    /// @return KE_OK, or the code of the extraction that failed.
    ke_result (*run)(ke_extraction *self, float dt, ke_completion **out_completion);
} ke_extraction;

/// [owner]
typedef struct ke_extraction_handle {
    ke_extraction *ref;
    void (*destroy)(ke_extraction *self);
} ke_extraction_handle;

#ifdef __cplusplus
}
#endif

#endif
