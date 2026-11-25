#ifndef KERNEL_ENGINE_FRAMEWORK_FRAMEWORK_PARTS_H_
#define KERNEL_ENGINE_FRAMEWORK_FRAMEWORK_PARTS_H_

#include <kernel_engine/framework/framework_log.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_framework contains, each named after its factory and with its slots named after the factory's
 * parameters: `scene_tree` (ke_scene_tree; `ecs`); `asset_resolver` (ke_asset_resolver; `image_loader` and
 * `font_loader`, optional, and `io`); `input_actions` (ke_input_actions); `input_actions_evaluation` (nothing;
 * `actions`, `input`, `pre_update`); `scene_hierarchy` (nothing; `ecs`, `post_update`); `node_types`
 * (ke_node_types; `scheduler`, `ecs`, `scene_tree` and `input_actions`, optional); `node_types_systems` (nothing;
 * `types`, `pre_update`, `fixed_update`, `update` and `post_update`); and `scene_files` (ke_scene_files; `ecs`,
 * `node_types`, `assets`, `io`, `first_scene`). A slot named after a phase takes the ke_schedule_set its systems join.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_FRAMEWORK_API const ke_part *ke_framework_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
