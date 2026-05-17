#include "../include/native_systems.hpp"
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/render/render.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>


namespace kernel_engine::render::core
{

struct ShadowSystemContext {
    uint32_t   light_cid;
    uint32_t   mesh_cid;
    uint32_t   transform_cid;
    ke_shadow_map_handle shadow_map_handle;
    uint32_t   reads[3];
};

void ShadowSystem::Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
{
    if (!world || !packet || !handle) return;

    ShadowSystemContext* ctx = static_cast<ShadowSystemContext*>(handle);
    ke_ecs_registry* reg = world->get_registry(world);

    // ── Find Directional Light ─────────────────────────────────────────────
    ke_entity* l_entities; void* l_data; size_t l_count;
    ke_ecs_registry_query(reg, ctx->light_cid, &l_entities, &l_data, &l_count);
    if (l_count == 0) return;

    // Shadow map must be pre-assigned by ke.render before the first frame.
    // GPU resource creation from ke.sim is not allowed.
    if (!ke_shadow_map_is_valid(ctx->shadow_map_handle)) return;

    ke_light_component* lights = static_cast<ke_light_component*>(l_data);

    // LightComponent.dir is the vector pointing FROM the surface TOWARD the light source
    // (matches LightNode.Direction convention used by fs_basic). To position the shadow
    // camera at the light, walk along +dir from the scene origin.
    ke_vec3 dir    = { lights[0].dir_x, lights[0].dir_y, lights[0].dir_z };
    ke_vec3 pos    = { dir.x * 25.0f, dir.y * 25.0f, dir.z * 25.0f };
    ke_vec3 target = { 0.0f, 0.0f, 0.0f };
    ke_vec3 up     = { 0.0f, 1.0f, 0.0f };

    ke_mat4_lookat(&packet->shadow.light_view, &pos, &target, &up);
    ke_mat4_ortho(&packet->shadow.light_proj, -20.0f, 20.0f, -20.0f, 20.0f, 0.1f, 50.0f);
    packet->shadow.map_handle = ctx->shadow_map_handle;

    // ── Find Shadow Casters ────────────────────────────────────────────────
    ke_entity* m_entities; void* m_data; size_t m_count;
    ke_ecs_registry_query(reg, ctx->mesh_cid, &m_entities, &m_data, &m_count);

    ke_mesh_component* meshes = static_cast<ke_mesh_component*>(m_data);

    for (size_t i = 0; i < m_count; i++)
    {
        if (!ke_mesh_is_valid(meshes[i].mesh_handle)) continue;

        ke_transform_component* tc = static_cast<ke_transform_component*>(
            ke_ecs_component_get(reg, m_entities[i], ctx->transform_cid));

        if (tc)
        {
            uint32_t index = atomic_fetch_add((_Atomic uint32_t*)&packet->shadow_draw_count, 1);
            if (index < packet->shadow_draw_capacity)
            {
                ke_draw_command* cmd = &packet->shadow_draw_commands[index];
                cmd->mesh_handle     = meshes[i].mesh_handle;
                cmd->material_handle = KE_MATERIAL_NONE;
                cmd->transform       = tc->world_matrix;
            }
        }
    }
}

ke_system_params ShadowSystem::GetDescription(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid)
{
    ShadowSystemContext* ctx = (ShadowSystemContext*)malloc(sizeof(ShadowSystemContext));
    ctx->light_cid        = light_cid;
    ctx->mesh_cid         = mesh_cid;
    ctx->transform_cid    = transform_cid;
    ctx->shadow_map_handle= KE_SHADOW_MAP_NONE;
    ctx->reads[0]         = light_cid;
    ctx->reads[1]         = mesh_cid;
    ctx->reads[2]         = transform_cid;

    ke_system_params desc = {};
    desc.name       = "ShadowSystem";
    desc.update     = ShadowSystem::Update;
    desc.handle     = ctx;
    desc.reads      = ctx->reads;
    desc.read_count = 3;
    return desc;
}

void ShadowSystem::SetShadowMap(ke_system_params* desc, ke_shadow_map_handle handle)
{
    if (!desc || !desc->handle) return;
    static_cast<ShadowSystemContext*>(desc->handle)->shadow_map_handle = handle;
}

} // namespace kernel_engine::render::core
