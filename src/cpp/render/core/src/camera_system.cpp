#include "../include/native_systems.hpp"
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <stdlib.h>
#include <math.h>

namespace kernel_engine::render::bgfx
{

struct CameraSystemContext {
    uint32_t camera_cid;
    uint32_t transform_cid;
    uint32_t reads[2];
};

void CameraSystem::Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
{
    if (!world || !packet || !handle) return;

    CameraSystemContext* ctx = static_cast<CameraSystemContext*>(handle);
    ke_ecs_registry* reg = world->get_registry(world);

    ke_entity* entities; void* data; size_t count;
    ke_ecs_registry_query(reg, ctx->camera_cid, &entities, &data, &count);

    if (count > 0)
    {
        ke_camera_component* cc = static_cast<ke_camera_component*>(data);
        ke_transform_component* tc = static_cast<ke_transform_component*>(
            ke_ecs_component_get(reg, entities[0], ctx->transform_cid));

        if (tc)
        {
            ke_mat4_inv(&packet->camera.view, &tc->world_matrix);

            // 16:9 aspect — camera component could carry this if needed in the future
            float aspect = 1.77f;
            if (cc->orthographic)
                ke_mat4_ortho(&packet->camera.proj, -aspect * 10.0f, aspect * 10.0f, -10.0f, 10.0f, cc->near_z, cc->far_z);
            else
                ke_mat4_proj(&packet->camera.proj, cc->fov, aspect, cc->near_z, cc->far_z);

            packet->camera.pos_x = tc->position.x;
            packet->camera.pos_y = tc->position.y;
            packet->camera.pos_z = tc->position.z;
        }
    }
}

ke_system_params CameraSystem::GetDescription(uint32_t camera_cid, uint32_t transform_cid)
{
    CameraSystemContext* ctx = (CameraSystemContext*)malloc(sizeof(CameraSystemContext));
    ctx->camera_cid    = camera_cid;
    ctx->transform_cid = transform_cid;
    ctx->reads[0]      = camera_cid;
    ctx->reads[1]      = transform_cid;

    ke_system_params desc = {};
    desc.name       = "CameraSystem";
    desc.update     = CameraSystem::Update;
    desc.handle     = ctx;
    desc.reads      = ctx->reads;
    desc.read_count = 2;
    return desc;
}

} // namespace kernel_engine::render::bgfx
