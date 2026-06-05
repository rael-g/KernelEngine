#include <kernel_engine/framework/light_render_system.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/engine/frame_packet.h>

#include <cstring>
#include <new>

// ── Internal state ───────────────────────────────────────────────────────────

struct ke_light_render_system
{
    ke_world         *world;
    ke_allocator     *allocator;
    ke_ecs_registry  *registry;
    ke_component_id   dir_cid;
    ke_component_id   point_cid;
    ke_component_id   spot_cid;
    ke_component_id   transform_cid;
    uint32_t          reads[4];
};

// ── Update tick ──────────────────────────────────────────────────────────────
//
// Mirrors C# LightRenderSystem.Update — first directional becomes the packet's
// single directional slot; each point/spot is appended with the position read
// from the entity's TransformComponent (defaulting to origin if absent).

static void light_update(void *handle, ke_world * /*world*/, float /*dt*/, ke_frame_packet *packet)
{
    if (!packet || !handle) return;
    auto *self = static_cast<ke_light_render_system *>(handle);

    // ── Directional ──────────────────────────────────────────────────────────
    {
        ke_entity *entities = nullptr;
        void      *data     = nullptr;
        size_t     count    = 0;
        ke_ecs_registry_query(self->registry, self->dir_cid, &entities, &data, &count);
        if (count > 0) {
            auto *lights = static_cast<const ke_directional_light_component *>(data);
            const auto &l = lights[0];
            packet->dir_light.dir_x = l.dir_x; packet->dir_light.dir_y = l.dir_y; packet->dir_light.dir_z = l.dir_z;
            packet->dir_light.r = l.r; packet->dir_light.g = l.g; packet->dir_light.b = l.b;
            packet->dir_light.intensity = l.intensity;
            packet->has_dir_light = true;
        }
    }

    // ── Point ────────────────────────────────────────────────────────────────
    if (packet->point_lights) {
        ke_entity *entities = nullptr;
        void      *data     = nullptr;
        size_t     count    = 0;
        ke_ecs_registry_query(self->registry, self->point_cid, &entities, &data, &count);
        auto *lights = static_cast<const ke_point_light_component *>(data);
        for (size_t i = 0; i < count; ++i) {
            if (packet->point_light_count >= packet->point_light_capacity) break;
            const auto &c = lights[i];
            auto *transform = static_cast<const ke_transform_component *>(
                ke_ecs_component_get(self->registry, entities[i], self->transform_cid));
            float px = transform ? transform->position.x : 0.0f;
            float py = transform ? transform->position.y : 0.0f;
            float pz = transform ? transform->position.z : 0.0f;
            ke_point_light *dst = &packet->point_lights[packet->point_light_count++];
            dst->pos_x = px; dst->pos_y = py; dst->pos_z = pz;
            dst->radius = c.radius;
            dst->r = c.r; dst->g = c.g; dst->b = c.b;
            dst->intensity = c.intensity;
        }
    }

    // ── Spot ─────────────────────────────────────────────────────────────────
    if (packet->spot_lights) {
        ke_entity *entities = nullptr;
        void      *data     = nullptr;
        size_t     count    = 0;
        ke_ecs_registry_query(self->registry, self->spot_cid, &entities, &data, &count);
        auto *lights = static_cast<const ke_spot_light_component *>(data);
        for (size_t i = 0; i < count; ++i) {
            if (packet->spot_light_count >= packet->spot_light_capacity) break;
            const auto &c = lights[i];
            auto *transform = static_cast<const ke_transform_component *>(
                ke_ecs_component_get(self->registry, entities[i], self->transform_cid));
            float px = transform ? transform->position.x : 0.0f;
            float py = transform ? transform->position.y : 0.0f;
            float pz = transform ? transform->position.z : 0.0f;
            ke_spot_light *dst = &packet->spot_lights[packet->spot_light_count++];
            dst->pos_x = px; dst->pos_y = py; dst->pos_z = pz;
            dst->range = c.range;
            dst->dir_x = c.dir_x; dst->dir_y = c.dir_y; dst->dir_z = c.dir_z;
            dst->inner_angle = c.inner_angle;
            dst->outer_angle = c.outer_angle;
            dst->r = c.r; dst->g = c.g; dst->b = c.b;
            dst->intensity = c.intensity;
        }
    }
}

// ── Factory ──────────────────────────────────────────────────────────────────

extern "C" ke_result ke_light_render_system_create(
    const ke_light_render_system_params *params,
    ke_light_render_system             **out_system)
{
    if (!params || !params->world || !params->allocator || !out_system) {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_ecs_registry *registry = params->world->get_registry(params->world);
    if (!registry) return KE_ERROR_NOT_INITIALIZED;

    auto *self = static_cast<ke_light_render_system *>(
        params->allocator->alloc(params->allocator, sizeof(ke_light_render_system), 0));
    if (!self) return KE_ERROR_OUT_OF_MEMORY;
    new (self) ke_light_render_system{};

    self->world         = params->world;
    self->allocator     = params->allocator;
    self->registry      = registry;
    self->dir_cid       = ke_ecs_component_register(registry, "ke_directional_light_component", sizeof(ke_directional_light_component));
    self->point_cid     = ke_ecs_component_register(registry, "ke_point_light_component",       sizeof(ke_point_light_component));
    self->spot_cid      = ke_ecs_component_register(registry, "ke_spot_light_component",        sizeof(ke_spot_light_component));
    self->transform_cid = params->world->transform_id(params->world);
    self->reads[0] = self->dir_cid;
    self->reads[1] = self->point_cid;
    self->reads[2] = self->spot_cid;
    self->reads[3] = self->transform_cid;

    *out_system = self;
    return KE_OK;
}

extern "C" void ke_light_render_system_destroy(ke_light_render_system *system)
{
    if (!system) return;
    ke_allocator *alloc = system->allocator;
    system->~ke_light_render_system();
    alloc->free(alloc, system);
}

extern "C" ke_component_id ke_light_render_system_directional_id(const ke_light_render_system *s) { return s ? s->dir_cid   : 0u; }
extern "C" ke_component_id ke_light_render_system_point_id      (const ke_light_render_system *s) { return s ? s->point_cid : 0u; }
extern "C" ke_component_id ke_light_render_system_spot_id       (const ke_light_render_system *s) { return s ? s->spot_cid  : 0u; }

extern "C" void ke_light_render_system_get_system_params(
    ke_light_render_system *system, ke_system_params *out_params)
{
    if (!out_params) return;
    *out_params = ke_system_params{};
    if (!system) return;
    out_params->name        = "ke_light_render_system";
    out_params->update      = light_update;
    out_params->handle      = system;
    out_params->reads       = system->reads;
    out_params->read_count  = 4;
    out_params->writes      = nullptr;
    out_params->write_count = 0;
}
