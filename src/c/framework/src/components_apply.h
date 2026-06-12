// Private to the framework plugin — do not include from outside src/c/framework/.
// Apply callbacks for the framework's built-in component vocabulary
// (kernel/framework/components.h). Each is registered against the world's
// apply registry at scene_tree create time so scene_loader can drive
// [entity.components.X] declaratively. Game components register their own.

#ifndef KE_FRAMEWORK_COMPONENTS_APPLY_H_
#define KE_FRAMEWORK_COMPONENTS_APPLY_H_

#include <kernel_engine/kernel/ecs/variant.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void ke_framework_apply_transform        (void *c, const ke_variant_table_entry *e, uint32_t n);
void ke_framework_apply_camera           (void *c, const ke_variant_table_entry *e, uint32_t n);
void ke_framework_apply_mesh             (void *c, const ke_variant_table_entry *e, uint32_t n);
void ke_framework_apply_directional_light(void *c, const ke_variant_table_entry *e, uint32_t n);
void ke_framework_apply_point_light      (void *c, const ke_variant_table_entry *e, uint32_t n);
void ke_framework_apply_spot_light       (void *c, const ke_variant_table_entry *e, uint32_t n);

#ifdef __cplusplus
}
#endif

#endif
