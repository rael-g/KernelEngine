#ifndef KERNEL_ENGINE_RENDER_MODULE_C_H_
#define KERNEL_ENGINE_RENDER_MODULE_C_H_

#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/spatial/transform.h>
#include <kernel_engine/spatial/component_fields.h>
#include <kernel_engine/framework/world.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/render/component_fields.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/service/pass_context.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/module/render_module_create.h>
#include <kernel_engine/render/module/scene_components.h>
#include <kernel_engine/framework/scene_component_set.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/render/skybox/skybox_create.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/render/ui/component_fields.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/logger/logger.h>

#endif
