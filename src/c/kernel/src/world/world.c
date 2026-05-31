#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/task_scheduler/task_scheduler.h>
#include <string.h>

#define KE_WORLD_MAX_SYSTEMS 64
#define KE_WORLD_MAX_WAVES   64

typedef struct ke_system_wave
{
    uint32_t system_indices[KE_WORLD_MAX_SYSTEMS];
    uint32_t system_count;
    bool     parallel;
} ke_system_wave;

typedef struct ke_world_impl
{
    struct ke_ecs_registry *registry;
    struct ke_allocator    *allocator;
    struct ke_task_scheduler *task_scheduler;

    ke_component_id transform_cid;
    ke_component_id hierarchy_cid;
    ke_component_id name_cid;
    ke_component_id script_cid;

    ke_system_params systems[KE_WORLD_MAX_SYSTEMS];
    size_t         system_count;

    ke_system_wave waves[KE_WORLD_MAX_WAVES];
    size_t         wave_count;
    bool           waves_dirty;

    ke_world api;
} ke_world_impl;

// ── Internal: Dependency Analysis ───────────────────────────────────────────

static bool systems_conflict(const ke_system_params *a, const ke_system_params *b)
{
    for (uint32_t i = 0; i < a->write_count; i++)
        for (uint32_t j = 0; j < b->write_count; j++)
            if (a->writes[i] == b->writes[j]) return true;

    for (uint32_t i = 0; i < a->write_count; i++)
        for (uint32_t j = 0; j < b->read_count; j++)
            if (a->writes[i] == b->reads[j]) return true;

    for (uint32_t i = 0; i < a->read_count; i++)
        for (uint32_t j = 0; j < b->write_count; j++)
            if (a->reads[i] == b->writes[j]) return true;

    return false;
}

static void rebuild_waves(ke_world_impl *impl)
{
    impl->wave_count = 0;
    if (impl->system_count == 0) return;

    ke_system_wave *current_wave = &impl->waves[impl->wave_count++];
    current_wave->system_count = 0;
    current_wave->parallel = true;

    for (uint32_t i = 0; i < (uint32_t)impl->system_count; i++)
    {
        const ke_system_params *sys = &impl->systems[i];
        bool is_serial_barrier = (sys->read_count == 0 && sys->write_count == 0);

        bool conflict_in_wave = false;
        if (!is_serial_barrier)
        {
            for (uint32_t j = 0; j < current_wave->system_count; j++)
            {
                if (systems_conflict(sys, &impl->systems[current_wave->system_indices[j]]))
                {
                    conflict_in_wave = true;
                    break;
                }
            }
        }

        if (is_serial_barrier || conflict_in_wave)
        {
            if (current_wave->system_count > 0)
            {
                current_wave->parallel = (current_wave->system_count > 1);
                current_wave = &impl->waves[impl->wave_count++];
            }
            
            current_wave->system_indices[0] = i;
            current_wave->system_count = 1;
            
            if (is_serial_barrier)
            {
                current_wave->parallel = false;
                current_wave = &impl->waves[impl->wave_count++];
                current_wave->system_count = 0;
                current_wave->parallel = true;
            }
        }
        else
        {
            current_wave->system_indices[current_wave->system_count++] = i;
        }
    }

    if (impl->wave_count > 0 && impl->waves[impl->wave_count - 1].system_count == 0)
        impl->wave_count--;
    else if (impl->wave_count > 0)
        impl->waves[impl->wave_count - 1].parallel = (impl->waves[impl->wave_count - 1].system_count > 1);

    impl->waves_dirty = false;
}

// ── Vtable accessors ──────────────────────────────────────────────────────────

static struct ke_ecs_registry *world_get_registry(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->registry;
}

static ke_component_id world_transform_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->transform_cid;
}

static ke_component_id world_hierarchy_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->hierarchy_cid;
}

static ke_component_id world_name_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->name_cid;
}

static ke_component_id world_script_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->script_cid;
}

static struct ke_task_scheduler* world_get_task_scheduler(ke_world* self)
{
    return ((ke_world_impl*)self->handle)->task_scheduler;
}

static ke_result world_add_system(ke_world *self, const ke_system_params *desc)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    if (impl->system_count >= KE_WORLD_MAX_SYSTEMS) return KE_ERROR_OUT_OF_MEMORY;
    impl->systems[impl->system_count++] = *desc;
    impl->waves_dirty = true;
    return KE_OK;
}

// ── Built-in systems ─────────────────────────────────────────────────────────

static void run_script_system(ke_world_impl *impl, const struct ke_frame *frame)
{
    ke_entity *entities;
    void      *data;
    size_t     count;
    ke_ecs_registry_query(impl->registry, impl->script_cid, &entities, &data, &count);

    float dt = frame ? (float)frame->delta_time : 0.0f;
    const ke_input_snapshot *input = frame ? frame->input : NULL;

    ke_script_component *scripts = (ke_script_component *)data;

    // Pass 1: awake → start → input → update
    for (size_t i = 0; i < count; i++)
    {
        ke_script_component *s = &scripts[i];
        if (s->state == KE_SCRIPT_STATE_FRESH)
        {
            s->state = KE_SCRIPT_STATE_AWOKE;
            if (s->on_awake) s->on_awake(entities[i]);
        }
        if (s->state == KE_SCRIPT_STATE_AWOKE)
        {
            s->state = KE_SCRIPT_STATE_STARTED;
            if (s->on_start) s->on_start(entities[i]);
        }
        if (s->on_input && input) s->on_input(entities[i], input);
        if (s->on_update) s->on_update(entities[i], dt);
    }

    // Pass 2: late_update (runs after every on_update in this frame)
    for (size_t i = 0; i < count; i++)
    {
        ke_script_component *s = &scripts[i];
        if (s->on_late_update) s->on_late_update(entities[i], dt);
    }
}

static void update_transform_recursive(ke_world_impl *impl, ke_entity entity,
                                       const ke_mat4 *parent_world)
{
    ke_transform_component *t = (ke_transform_component *)ke_ecs_component_get(
        impl->registry, entity, impl->transform_cid);
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_get(
        impl->registry, entity, impl->hierarchy_cid);
    if (!t) return;

    ke_mat4 local;
    ke_mat4_from_transform(&local, &t->position, &t->rotation, &t->scale);

    // System.Numerics.Matrix4x4 (and our ke_mat4 byte layout — translation at m[12..14]) is
    // row-major / row-vector. Composition rule: world = local * parent (apply local first, then
    // parent's transform). Doing `parent * local` works only when the parent is identity (e.g.
    // top-level nodes under the Root) — every 2-deep hierarchy gets the child's translation
    // multiplied by the parent's scale instead of added to the parent's translation.
    if (parent_world)
        ke_mat4_mul(&t->world_matrix, &local, parent_world);
    else
        t->world_matrix = local;

    if (!h) return;
    ke_entity child = h->first_child;
    while (child != KE_ENTITY_INVALID)
    {
        update_transform_recursive(impl, child, &t->world_matrix);
        // Find next sibling
        ke_hierarchy_component *ch = (ke_hierarchy_component *)ke_ecs_component_get(impl->registry, child, impl->hierarchy_cid);
        if (!ch) break;
        child = ch->next_sibling;
    }
}

static void update_transforms(ke_world_impl *impl)
{
    ke_entity *entities;
    void      *data;
    size_t     count;
    ke_ecs_registry_query(impl->registry, impl->hierarchy_cid, &entities, &data, &count);

    ke_hierarchy_component *hierarchies = (ke_hierarchy_component *)data;
    for (size_t i = 0; i < count; i++)
    {
        if (hierarchies[i].parent == KE_ENTITY_INVALID)
            update_transform_recursive(impl, entities[i], NULL);
    }
}

// ── Parallel Execution Wrapper ───────────────────────────────────────────────

typedef struct ke_system_task_data {
    ke_world*       world;
    ke_system_params* sys;
    float           dt;
} ke_system_task_data;

static void system_task_entry(void* data) {
    ke_system_task_data* task = (ke_system_task_data*)data;
    task->sys->update(task->sys->handle, task->world, task->dt, NULL); 
}

// ── Update ────────────────────────────────────────────────────────────────────

static ke_result world_update(ke_world *self, const struct ke_frame *frame)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    float dt = frame ? (float)frame->delta_time : 0.0f;

    run_script_system(impl, frame);
    update_transforms(impl);

    if (impl->waves_dirty) rebuild_waves(impl);

    for (size_t w = 0; w < impl->wave_count; w++)
    {
        ke_system_wave *wave = &impl->waves[w];
        if (!wave->parallel || !impl->task_scheduler)
        {
            for (uint32_t s = 0; s < wave->system_count; s++)
            {
                ke_system_params *sys = &impl->systems[wave->system_indices[s]];
                sys->update(sys->handle, self, dt, NULL);
            }
        }
        else
        {
            ke_task* tasks[KE_WORLD_MAX_SYSTEMS];
            ke_system_task_data task_data[KE_WORLD_MAX_SYSTEMS];
            
            for (uint32_t s = 0; s < wave->system_count; s++)
            {
                ke_system_params *sys = &impl->systems[wave->system_indices[s]];
                task_data[s].world  = self;
                task_data[s].sys    = sys;
                task_data[s].dt     = dt;
                tasks[s] = impl->task_scheduler->dispatch(impl->task_scheduler, system_task_entry, &task_data[s]);
            }
            
            for (uint32_t s = 0; s < wave->system_count; s++)
                impl->task_scheduler->wait(impl->task_scheduler, tasks[s]);
        }
    }

    return KE_OK;
}

// ── Script notify destroy ─────────────────────────────────────────────────────

ke_result ke_world_notify_destroy(ke_world *world, ke_entity entity)
{
    if (!world || entity == 0) return KE_ERROR_INVALID_ARGUMENT;
    ke_world_impl *impl = (ke_world_impl *)world->handle;
    ke_script_component *s = (ke_script_component *)ke_ecs_component_get(
        impl->registry, entity, impl->script_cid);
    if (!s) return KE_OK; // entity has no script component — not an error
    if (s->on_destroy) s->on_destroy(entity);
    return KE_OK;
}

// ── Destroy ───────────────────────────────────────────────────────────────────

static void world_destroy(ke_world *self)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    ke_ecs_registry_destroy(impl->registry);
    impl->allocator->free(impl->allocator, impl);
}

// ── Factory ───────────────────────────────────────────────────────────────────

ke_result ke_world_create(const ke_world_params *params, ke_world **out_world)
{
    if (!params || !params->allocator || !out_world) return KE_ERROR_INVALID_ARGUMENT;

    ke_world_impl *impl = (ke_world_impl *)params->allocator->alloc(
        params->allocator, sizeof(ke_world_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    memset(impl, 0, sizeof(ke_world_impl));
    impl->allocator = params->allocator;

    ke_result res = ke_ecs_registry_create(impl->allocator, &impl->registry);
    if (res != KE_OK)
    {
        impl->allocator->free(impl->allocator, impl);
        return res;
    }

    impl->transform_cid = ke_ecs_component_register(impl->registry, "ke_transform", sizeof(ke_transform_component));
    impl->hierarchy_cid = ke_ecs_component_register(impl->registry, "ke_hierarchy", sizeof(ke_hierarchy_component));
    impl->name_cid      = ke_ecs_component_register(impl->registry, "ke_name",      sizeof(ke_name_component));
    impl->script_cid    = ke_ecs_component_register(impl->registry, "ke_script",    sizeof(ke_script_component));

    impl->api.handle       = impl;
    impl->api.destroy      = world_destroy;
    impl->api.get_registry = world_get_registry;
    impl->api.update       = world_update;
    impl->api.add_system   = world_add_system;
    impl->api.transform_id = world_transform_id;
    impl->api.hierarchy_id = world_hierarchy_id;
    impl->api.name_id      = world_name_id;
    impl->api.script_id    = world_script_id;
    impl->api.get_task_scheduler = world_get_task_scheduler;

    *out_world = &impl->api;
    return KE_OK;
}
