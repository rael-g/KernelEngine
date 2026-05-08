#include "../include/native_systems.hpp"
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <string.h>
#include <stdlib.h>

namespace kernel_engine::render::bgfx
{

struct LightSystemContext {
    uint32_t light_cid;
    uint32_t point_cid;
    uint32_t spot_cid;
    uint32_t transform_cid;
    uint32_t reads[4];
};

void LightSystem::Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
{
    if (!world || !packet || !handle) return;

    LightSystemContext* ctx = static_cast<LightSystemContext*>(handle);
    ke_ecs_registry* reg = world->get_registry(world);

    // ── Directional light ──────────────────────────────────────────────────
    {
        ke_entity* entities; void* data; size_t count;
        ke_ecs_registry_query(reg, ctx->light_cid, &entities, &data, &count);
        if (count > 0)
        {
            ke_light_component* lights = static_cast<ke_light_component*>(data);
            packet->dir_light.dir_x    = lights[0].dir_x;
            packet->dir_light.dir_y    = lights[0].dir_y;
            packet->dir_light.dir_z    = lights[0].dir_z;
            packet->dir_light.r        = lights[0].r;
            packet->dir_light.g        = lights[0].g;
            packet->dir_light.b        = lights[0].b;
            packet->dir_light.intensity= lights[0].intensity;
            packet->has_dir_light      = true;
        }
    }

    // ── Point lights ───────────────────────────────────────────────────────
    {
        ke_entity* entities; void* data; size_t count;
        ke_ecs_registry_query(reg, ctx->point_cid, &entities, &data, &count);
        uint32_t to_copy = (uint32_t)(count < packet->point_light_capacity ? count : packet->point_light_capacity);

        ke_point_light_component* comps = static_cast<ke_point_light_component*>(data);
        for (uint32_t i = 0; i < to_copy; i++)
        {
            ke_transform_component* tc = static_cast<ke_transform_component*>(
                ke_ecs_component_get(reg, entities[i], ctx->transform_cid));

            packet->point_lights[i].pos_x     = tc ? tc->position.x : 0.0f;
            packet->point_lights[i].pos_y     = tc ? tc->position.y : 0.0f;
            packet->point_lights[i].pos_z     = tc ? tc->position.z : 0.0f;
            packet->point_lights[i].radius    = comps[i].radius;
            packet->point_lights[i].r         = comps[i].r;
            packet->point_lights[i].g         = comps[i].g;
            packet->point_lights[i].b         = comps[i].b;
            packet->point_lights[i].intensity = comps[i].intensity;
        }
        packet->point_light_count = to_copy;
    }

    // ── Spot lights ────────────────────────────────────────────────────────
    {
        ke_entity* entities; void* data; size_t count;
        ke_ecs_registry_query(reg, ctx->spot_cid, &entities, &data, &count);
        uint32_t to_copy = (uint32_t)(count < packet->spot_light_capacity ? count : packet->spot_light_capacity);

        ke_spot_light_component* comps = static_cast<ke_spot_light_component*>(data);
        for (uint32_t i = 0; i < to_copy; i++)
        {
            ke_transform_component* tc = static_cast<ke_transform_component*>(
                ke_ecs_component_get(reg, entities[i], ctx->transform_cid));

            packet->spot_lights[i].pos_x       = tc ? tc->position.x : 0.0f;
            packet->spot_lights[i].pos_y       = tc ? tc->position.y : 0.0f;
            packet->spot_lights[i].pos_z       = tc ? tc->position.z : 0.0f;
            packet->spot_lights[i].range       = comps[i].range;
            packet->spot_lights[i].dir_x       = comps[i].dir_x;
            packet->spot_lights[i].dir_y       = comps[i].dir_y;
            packet->spot_lights[i].dir_z       = comps[i].dir_z;
            packet->spot_lights[i].inner_angle = comps[i].inner_angle;
            packet->spot_lights[i].outer_angle = comps[i].outer_angle;
            packet->spot_lights[i].r           = comps[i].r;
            packet->spot_lights[i].g           = comps[i].g;
            packet->spot_lights[i].b           = comps[i].b;
            packet->spot_lights[i].intensity   = comps[i].intensity;
        }
        packet->spot_light_count = to_copy;
    }
}

ke_system_params LightSystem::GetDescription(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid)
{
    LightSystemContext* ctx = (LightSystemContext*)malloc(sizeof(LightSystemContext));
    ctx->light_cid      = light_cid;
    ctx->point_cid      = point_cid;
    ctx->spot_cid       = spot_cid;
    ctx->transform_cid  = transform_cid;
    ctx->reads[0]       = light_cid;
    ctx->reads[1]       = point_cid;
    ctx->reads[2]       = spot_cid;
    ctx->reads[3]       = transform_cid;

    ke_system_params desc = {};
    desc.name       = "LightSystem";
    desc.update     = LightSystem::Update;
    desc.handle     = ctx;
    desc.reads      = ctx->reads;
    desc.read_count = 4;
    return desc;
}

} // namespace kernel_engine::render::bgfx
