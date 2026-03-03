#include <kernel_engine/core/common/hash_map.h>
#include <kernel_engine/core/context/allocator.h>
#include <string.h>

ke_result ke_hash_map_init(ke_hash_map *map, size_t initial_capacity, ke_allocator *alloc)
{
    if (!map || !alloc)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    map->allocator = alloc;
    map->size = 0;
    map->capacity = initial_capacity;
    map->entries = (ke_hash_map_entry *)alloc->alloc(alloc, initial_capacity * sizeof(ke_hash_map_entry), 0);
    if (map->entries)
    {
        memset(map->entries, 0, initial_capacity * sizeof(ke_hash_map_entry));
        return KE_OK;
    }
    return KE_ERROR_OUT_OF_MEMORY;
}

void ke_hash_map_destroy(ke_hash_map *map)
{
    if (map && map->entries && map->allocator)
    {
        map->allocator->free(map->allocator, map->entries);
        map->entries = NULL;
        map->size = 0;
        map->capacity = 0;
    }
}

static ke_result ke_hash_map_rehash(ke_hash_map *map)
{
    size_t old_capacity = map->capacity;
    ke_hash_map_entry *old_entries = map->entries;
    ke_allocator *alloc = map->allocator;

    size_t new_cap = old_capacity * 2;
    ke_hash_map_entry *new_entries = (ke_hash_map_entry *)alloc->alloc(alloc, new_cap * sizeof(ke_hash_map_entry), 0);
    if (!new_entries)
    {
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(new_entries, 0, new_cap * sizeof(ke_hash_map_entry));

    map->entries = new_entries;
    map->capacity = new_cap;
    map->size = 0;

    for (size_t i = 0; i < old_capacity; ++i)
    {
        if (old_entries[i].key != 0)
        {
            ke_hash_map_insert(map, old_entries[i].key, old_entries[i].value);
        }
    }
    alloc->free(alloc, old_entries);
    return KE_OK;
}

ke_result ke_hash_map_insert(ke_hash_map *map, uint64_t key, void *value)
{
    if (!map || !map->entries)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    if (map->size >= (size_t)(map->capacity * 0.7))
    {
        ke_result res = ke_hash_map_rehash(map);
        if (res != KE_OK)
        {
            return res;
        }
    }
    size_t index = key % map->capacity;
    while (map->entries[index].key != 0 && map->entries[index].key != key)
    {
        index = (index + 1) % map->capacity;
    }
    if (map->entries[index].key == 0)
    {
        map->size++;
    }
    map->entries[index].key = key;
    map->entries[index].value = value;
    return KE_OK;
}

void *ke_hash_map_get(const ke_hash_map *map, uint64_t key)
{
    if (!map->entries || map->capacity == 0)
    {
        return NULL;
    }
    size_t index = key % map->capacity;
    size_t start = index;
    while (map->entries[index].key != 0)
    {
        if (map->entries[index].key == key)
        {
            return map->entries[index].value;
        }
        index = (index + 1) % map->capacity;
        if (index == start)
        {
            break;
        }
    }
    return NULL;
}
