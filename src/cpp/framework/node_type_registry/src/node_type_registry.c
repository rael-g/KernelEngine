#include <kernel_engine/framework/node_type_registry_create.h>
#include <kernel_engine/kernel/common/hash.h>
#include <kernel_engine/kernel/common/hash_map.h>
#include <string.h>
#include <stdlib.h>

// ── Internal state ────────────────────────────────────────────────────────────

typedef struct ke_node_type_registry_impl
{
    ke_node_type_registry api;
    ke_allocator         *allocator;
    ke_hash_map           map; // uint64_t(hash of name) → ke_node_type*
} ke_node_type_registry_impl;

// ── vtable implementations ────────────────────────────────────────────────────

static ke_result registry_register_type(ke_node_type_registry *self,
                                         const ke_node_type    *type)
{
    if (!self || !type || !type->name || !type->create)
        return KE_ERROR_INVALID_ARGUMENT;

    ke_node_type_registry_impl *impl = (ke_node_type_registry_impl *)self->handle;

    // Allocate a copy of the descriptor so the caller doesn't need to keep it alive.
    ke_node_type *copy = (ke_node_type *)impl->allocator->alloc(
        impl->allocator, sizeof(ke_node_type), 0);
    if (!copy) return KE_ERROR_OUT_OF_MEMORY;
    *copy = *type;

    uint64_t key = ke_hash_string(type->name);
    ke_result res = ke_hash_map_insert(&impl->map, key, copy);
    if (res != KE_OK)
    {
        impl->allocator->free(impl->allocator, copy);
        return res;
    }
    return KE_OK;
}

static ke_result registry_lookup(ke_node_type_registry *self,
                                  const char            *name,
                                  const ke_node_type   **out_type)
{
    if (!self || !name || !out_type) return KE_ERROR_INVALID_ARGUMENT;

    ke_node_type_registry_impl *impl = (ke_node_type_registry_impl *)self->handle;
    uint64_t key = ke_hash_string(name);
    ke_node_type *found = (ke_node_type *)ke_hash_map_get(&impl->map, key);
    if (!found) return KE_ERROR_NOT_FOUND;

    *out_type = found;
    return KE_OK;
}

static void registry_destroy(ke_node_type_registry *self)
{
    if (!self) return;
    ke_node_type_registry_impl *impl = (ke_node_type_registry_impl *)self->handle;

    // Free each copied ke_node_type entry.
    for (size_t i = 0; i < impl->map.capacity; i++)
    {
        if (impl->map.entries[i].key != 0 && impl->map.entries[i].value)
            impl->allocator->free(impl->allocator, impl->map.entries[i].value);
    }

    ke_hash_map_destroy(&impl->map);
    impl->allocator->free(impl->allocator, impl);
}

// ── Factory ───────────────────────────────────────────────────────────────────

ke_result ke_node_type_registry_create(ke_allocator           *alloc,
                                        ke_node_type_registry **out_registry)
{
    if (!alloc || !out_registry) return KE_ERROR_INVALID_ARGUMENT;

    ke_node_type_registry_impl *impl = (ke_node_type_registry_impl *)alloc->alloc(
        alloc, sizeof(ke_node_type_registry_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    memset(impl, 0, sizeof(ke_node_type_registry_impl));
    impl->allocator = alloc;

    ke_result res = ke_hash_map_init(&impl->map, 64, alloc);
    if (res != KE_OK)
    {
        alloc->free(alloc, impl);
        return res;
    }

    impl->api.handle         = impl;
    impl->api.register_type  = registry_register_type;
    impl->api.lookup          = registry_lookup;
    impl->api.destroy         = registry_destroy;

    *out_registry = &impl->api;
    return KE_OK;
}
