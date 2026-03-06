#ifndef KERNEL_ENGINE_KERNEL_COMMON_HASH_MAP_H_
#define KERNEL_ENGINE_KERNEL_COMMON_HASH_MAP_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Entry in the hash map.
    typedef struct ke_hash_map_entry
    {
        uint64_t key;
        void *value;
    } ke_hash_map_entry;

    /// @brief Simple hash map implementation.
    typedef struct ke_hash_map
    {
        ke_hash_map_entry *entries;
        size_t size;
        size_t capacity;
        struct ke_allocator *allocator;
    } ke_hash_map;

    /// @brief Initializes a hash map.
    KE_API ke_result ke_hash_map_init(ke_hash_map *map, size_t initial_capacity, struct ke_allocator *alloc);

    /// @brief Destroys a hash map.
    KE_API void ke_hash_map_destroy(ke_hash_map *map);

    /// @brief Inserts a value into the hash map.
    KE_API ke_result ke_hash_map_insert(ke_hash_map *map, uint64_t key, void *value);

    /// @brief Retrieves a value from the hash map.
    KE_API void *ke_hash_map_get(const ke_hash_map *map, uint64_t key);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_HASH_MAP_H_
