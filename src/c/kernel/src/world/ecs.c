#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/ke_ecs.h>
#include <kernel_engine/kernel/common/array.h>
#include <kernel_engine/kernel/common/hash_map.h>
#include <stdlib.h>
#include <string.h>

typedef struct ke_component_type
{
    char name[64];
    size_t size;
    void *data; // Contiguous array of component data
    ke_array entities; // Entities that have this component
    ke_hash_map entity_to_index; // Maps ke_entity to index in 'data' and 'entities'
    size_t capacity;

    // Field metadata (Phase 1 of the ECS-pure node refactor). `fields` is owned
    // by the registry — allocated via the registry allocator on register_v2,
    // freed in registry_destroy. NULL when registered via the legacy
    // ke_ecs_component_register (no fields → component is opaque to the scene
    // loader, only reachable through native code).
    ke_component_field *fields;
    uint32_t field_count;
} ke_component_type;

typedef struct ke_ecs_registry_internal
{
    ke_array component_types; // Array of ke_component_type*
} ke_ecs_registry_internal;

ke_result ke_ecs_registry_create(struct ke_allocator *alloc, ke_ecs_registry **out_registry)
{
    if (!alloc || !out_registry) return KE_ERROR_INVALID_ARGUMENT;

    ke_ecs_registry *reg = (ke_ecs_registry *)alloc->alloc(alloc, sizeof(ke_ecs_registry), 0);
    if (!reg) return KE_ERROR_OUT_OF_MEMORY;

    reg->allocator = alloc;
    reg->next_entity = 1; // 0 is invalid

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)alloc->alloc(alloc, sizeof(ke_ecs_registry_internal), 0);
    if (!internal)
    {
        alloc->free(alloc, reg);
        return KE_ERROR_OUT_OF_MEMORY;
    }

    ke_array_init(&internal->component_types, 16, alloc);
    reg->internal_data = internal;

    *out_registry = reg;
    return KE_OK;
}

void ke_ecs_registry_destroy(ke_ecs_registry *registry)
{
    if (!registry) return;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    for (size_t i = 0; i < internal->component_types.size; ++i)
    {
        ke_component_type *type = (ke_component_type *)internal->component_types.data[i];
        if (type->data)   registry->allocator->free(registry->allocator, type->data);
        if (type->fields) registry->allocator->free(registry->allocator, type->fields);
        ke_array_destroy(&type->entities);
        ke_hash_map_destroy(&type->entity_to_index);
        registry->allocator->free(registry->allocator, type);
    }
    ke_array_destroy(&internal->component_types);
    registry->allocator->free(registry->allocator, internal);
    registry->allocator->free(registry->allocator, registry);
}

ke_entity ke_ecs_entity_create(ke_ecs_registry *registry)
{
    if (!registry) return KE_ENTITY_INVALID;
    return registry->next_entity++;
}

void ke_ecs_entity_destroy(ke_ecs_registry *registry, ke_entity entity)
{
    if (!registry || entity == KE_ENTITY_INVALID) return;
    
    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    for (size_t i = 0; i < internal->component_types.size; ++i)
    {
        ke_ecs_component_remove(registry, entity, (ke_component_id)i);
    }
}

ke_component_id ke_ecs_component_register(ke_ecs_registry *registry, const char *name, size_t size)
{
    return ke_ecs_component_register_v2(registry, name, size, NULL, 0);
}

ke_component_id ke_ecs_component_register_v2(
    ke_ecs_registry           *registry,
    const char                *name,
    size_t                     size,
    const ke_component_field  *fields,
    uint32_t                   field_count)
{
    if (!registry || !name) return KE_COMPONENT_INVALID;
    if (field_count > 0 && !fields) return KE_COMPONENT_INVALID;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    ke_component_type *type = (ke_component_type *)registry->allocator->alloc(
        registry->allocator, sizeof(ke_component_type), 0);
    if (!type) return KE_COMPONENT_INVALID;

    memset(type, 0, sizeof(*type));
    strncpy(type->name, name, sizeof(type->name) - 1);
    type->size = size;
    type->capacity = 32;
    type->data = registry->allocator->alloc(registry->allocator, size * type->capacity, 0);
    ke_array_init(&type->entities, type->capacity, registry->allocator);
    ke_hash_map_init(&type->entity_to_index, type->capacity, registry->allocator);

    if (field_count > 0) {
        size_t fbytes = sizeof(ke_component_field) * field_count;
        type->fields = (ke_component_field *)registry->allocator->alloc(
            registry->allocator, fbytes, 0);
        if (!type->fields) {
            if (type->data) registry->allocator->free(registry->allocator, type->data);
            ke_array_destroy(&type->entities);
            ke_hash_map_destroy(&type->entity_to_index);
            registry->allocator->free(registry->allocator, type);
            return KE_COMPONENT_INVALID;
        }
        memcpy(type->fields, fields, fbytes);
        type->field_count = field_count;
    }

    ke_array_push(&internal->component_types, type);
    return (ke_component_id)(internal->component_types.size - 1);
}

ke_result ke_ecs_component_lookup(ke_ecs_registry *registry, const char *name,
                                  ke_component_meta *out_meta)
{
    if (!registry || !name || !out_meta) return KE_ERROR_INVALID_ARGUMENT;
    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    for (size_t i = 0; i < internal->component_types.size; ++i) {
        ke_component_type *t = (ke_component_type *)internal->component_types.data[i];
        if (strncmp(t->name, name, sizeof(t->name)) == 0) {
            out_meta->cid         = (ke_component_id)i;
            out_meta->size        = t->size;
            out_meta->fields      = t->fields;
            out_meta->field_count = t->field_count;
            return KE_OK;
        }
    }
    return KE_ERROR_NOT_FOUND;
}

// Decode a variant into a component field. The component pointer is already
// resolved to the entity's slot; we only need offset + type compatibility.
static ke_result write_variant_at_field(void *comp, const ke_component_field *f,
                                        const ke_variant *v)
{
    void *dst = (uint8_t *)comp + f->offset;
    if (f->type == v->type) {
        switch (f->type) {
            case KE_VARIANT_BOOL:   *(uint8_t  *)dst = v->b ? 1 : 0; return KE_OK;
            case KE_VARIANT_INT:    *(int32_t  *)dst = (int32_t)v->i; return KE_OK;
            case KE_VARIANT_FLOAT:  *(float    *)dst = (float)v->f; return KE_OK;
            case KE_VARIANT_STRING:
                if (f->size > 0) {
                    // Copy into a fixed buffer so the value survives the variant's
                    // transient string. Reserve one byte for the terminator.
                    char *buf = (char *)dst;
                    if (v->s) {
                        size_t n = 0;
                        while (v->s[n] && n + 1 < f->size) { buf[n] = v->s[n]; ++n; }
                        buf[n] = '\0';
                    } else {
                        buf[0] = '\0';
                    }
                } else {
                    *(const char **)dst = v->s;
                }
                return KE_OK;
            case KE_VARIANT_VEC2:   memcpy(dst, &v->v2, sizeof(ke_vec2)); return KE_OK;
            case KE_VARIANT_VEC3:   memcpy(dst, &v->v3, sizeof(ke_vec3)); return KE_OK;
            case KE_VARIANT_VEC4:   memcpy(dst, &v->v4, sizeof(ke_vec4)); return KE_OK;
            case KE_VARIANT_QUAT:   memcpy(dst, &v->q,  sizeof(ke_quat)); return KE_OK;
            case KE_VARIANT_NULL:
            case KE_VARIANT_TABLE:  return KE_ERROR_NOT_SUPPORTED;
        }
        return KE_ERROR_NOT_SUPPORTED;
    }
    // Single allowance: TOML int parsed for a float field.
    if (f->type == KE_VARIANT_FLOAT && v->type == KE_VARIANT_INT) {
        *(float *)dst = (float)v->i;
        return KE_OK;
    }
    return KE_ERROR_INVALID_ARGUMENT;
}

ke_result ke_ecs_component_apply_variant(
    ke_ecs_registry  *registry,
    ke_entity         entity,
    ke_component_id   cid,
    const char       *field_name,
    const ke_variant *value)
{
    if (!registry || entity == KE_ENTITY_INVALID || !field_name || !value)
        return KE_ERROR_INVALID_ARGUMENT;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    if (cid >= internal->component_types.size) return KE_ERROR_NOT_FOUND;
    ke_component_type *t = (ke_component_type *)internal->component_types.data[cid];

    void *comp = ke_ecs_component_get(registry, entity, cid);
    if (!comp) return KE_ERROR_NOT_FOUND;

    for (uint32_t i = 0; i < t->field_count; ++i) {
        if (strcmp(t->fields[i].name, field_name) == 0) {
            return write_variant_at_field(comp, &t->fields[i], value);
        }
    }
    return KE_ERROR_NOT_FOUND;
}

void *ke_ecs_component_add(ke_ecs_registry *registry, ke_entity entity, ke_component_id component)
{
    if (!registry || entity == KE_ENTITY_INVALID) return NULL;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    if (component >= internal->component_types.size) return NULL;

    ke_component_type *type = (ke_component_type *)internal->component_types.data[component];
    
    // Check if already exists
    void *existing = ke_hash_map_get(&type->entity_to_index, entity);
    if (existing) return (uint8_t *)type->data + ((uintptr_t)existing - 1) * type->size;

    // Resize if needed
    if (type->entities.size >= type->capacity)
    {
        size_t new_cap = type->capacity * 2;
        type->data = registry->allocator->realloc(registry->allocator, type->data, type->size * new_cap);
        type->capacity = new_cap;
    }

    size_t index = type->entities.size;
    ke_array_push(&type->entities, (void *)(uintptr_t)entity);
    ke_hash_map_insert(&type->entity_to_index, entity, (void *)(uintptr_t)(index + 1));

    void *comp_ptr = (uint8_t *)type->data + index * type->size;
    memset(comp_ptr, 0, type->size);
    return comp_ptr;
}

void ke_ecs_component_remove(ke_ecs_registry *registry, ke_entity entity, ke_component_id component)
{
    // Simple remove: swap with last to maintain contiguous data
    if (!registry || entity == KE_ENTITY_INVALID) return;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    if (component >= internal->component_types.size) return;

    ke_component_type *type = (ke_component_type *)internal->component_types.data[component];
    void *existing = ke_hash_map_get(&type->entity_to_index, entity);
    if (!existing) return;

    size_t index = (size_t)((uintptr_t)existing - 1);
    size_t last_index = type->entities.size - 1;

    if (index != last_index)
    {
        ke_entity last_entity = (ke_entity)(uintptr_t)type->entities.data[last_index];
        
        // Swap data
        memcpy((uint8_t *)type->data + index * type->size, 
               (uint8_t *)type->data + last_index * type->size, 
               type->size);
        
        // Update swap-entity index
        type->entities.data[index] = (void *)(uintptr_t)last_entity;
        ke_hash_map_insert(&type->entity_to_index, last_entity, (void *)(uintptr_t)(index + 1));
    }

    type->entities.size--;
    // ke_hash_map does not have "remove" yet, we should probably add it or set to NULL
    // For now, we overwrite with 0 to mark as removed in the map logic if we adjust it
    ke_hash_map_insert(&type->entity_to_index, entity, NULL);
}

void *ke_ecs_component_get(ke_ecs_registry *registry, ke_entity entity, ke_component_id component)
{
    if (!registry || entity == KE_ENTITY_INVALID) return NULL;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    if (component >= internal->component_types.size) return NULL;

    ke_component_type *type = (ke_component_type *)internal->component_types.data[component];
    void *existing = ke_hash_map_get(&type->entity_to_index, entity);
    if (!existing) return NULL;

    return (uint8_t *)type->data + ((uintptr_t)existing - 1) * type->size;
}

void ke_ecs_registry_query(ke_ecs_registry *registry, ke_component_id component,
                           ke_entity **out_entities, void **out_data, size_t *out_count)
{
    if (!registry || !out_entities || !out_data || !out_count) return;

    ke_ecs_registry_internal *internal = (ke_ecs_registry_internal *)registry->internal_data;
    if (component >= internal->component_types.size)
    {
        *out_entities = NULL;
        *out_data = NULL;
        *out_count = 0;
        return;
    }

    ke_component_type *type = (ke_component_type *)internal->component_types.data[component];
    *out_entities = (ke_entity *)type->entities.data;
    *out_data = type->data;
    *out_count = type->entities.size;
}

// ── ke_ecs vtable — sparse-set backend ───────────────────────────────────────

typedef struct ke_ecs_sparse_impl
{
    ke_ecs           api;
    ke_ecs_registry *registry;
    ke_allocator    *allocator;
} ke_ecs_sparse_impl;

static ke_entity sparse_entity_create(ke_ecs *self)
{
    return ke_ecs_entity_create(((ke_ecs_sparse_impl *)self->handle)->registry);
}

static void sparse_entity_destroy(ke_ecs *self, ke_entity entity)
{
    ke_ecs_entity_destroy(((ke_ecs_sparse_impl *)self->handle)->registry, entity);
}

static ke_component_id sparse_component_register(ke_ecs *self, const char *name, size_t size)
{
    return ke_ecs_component_register(((ke_ecs_sparse_impl *)self->handle)->registry, name, size);
}

static ke_result sparse_component_lookup(ke_ecs *self, const char *name, ke_component_meta *out_meta)
{
    return ke_ecs_component_lookup(((ke_ecs_sparse_impl *)self->handle)->registry, name, out_meta);
}

static void *sparse_component_add(ke_ecs *self, ke_entity entity, ke_component_id cid)
{
    return ke_ecs_component_add(((ke_ecs_sparse_impl *)self->handle)->registry, entity, cid);
}

static void sparse_component_remove(ke_ecs *self, ke_entity entity, ke_component_id cid)
{
    ke_ecs_component_remove(((ke_ecs_sparse_impl *)self->handle)->registry, entity, cid);
}

static void *sparse_component_get(ke_ecs *self, ke_entity entity, ke_component_id cid)
{
    return ke_ecs_component_get(((ke_ecs_sparse_impl *)self->handle)->registry, entity, cid);
}

static void sparse_query(ke_ecs *self, ke_component_id cid,
                         ke_entity **out_entities, void **out_data, size_t *out_count)
{
    ke_ecs_registry_query(((ke_ecs_sparse_impl *)self->handle)->registry,
                          cid, out_entities, out_data, out_count);
}

static void sparse_destroy(ke_ecs *self)
{
    ke_ecs_sparse_impl *impl = (ke_ecs_sparse_impl *)self->handle;
    impl->allocator->free(impl->allocator, impl);
}

ke_result ke_ecs_sparse_set_create(ke_ecs_registry *registry,
                                    ke_allocator    *alloc,
                                    ke_ecs         **out_ecs)
{
    if (!registry || !alloc || !out_ecs) return KE_ERROR_INVALID_ARGUMENT;

    ke_ecs_sparse_impl *impl = (ke_ecs_sparse_impl *)alloc->alloc(
        alloc, sizeof(ke_ecs_sparse_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    impl->registry = registry;
    impl->allocator = alloc;

    impl->api.handle             = impl;
    impl->api.entity_create      = sparse_entity_create;
    impl->api.entity_destroy     = sparse_entity_destroy;
    impl->api.component_register = sparse_component_register;
    impl->api.component_lookup   = sparse_component_lookup;
    impl->api.component_add      = sparse_component_add;
    impl->api.component_remove   = sparse_component_remove;
    impl->api.component_get      = sparse_component_get;
    impl->api.query              = sparse_query;
    impl->api.destroy            = sparse_destroy;

    *out_ecs = &impl->api;
    return KE_OK;
}
