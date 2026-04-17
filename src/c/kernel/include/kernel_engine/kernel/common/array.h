#ifndef KERNEL_ENGINE_KERNEL_COMMON_ARRAY_H_
#define KERNEL_ENGINE_KERNEL_COMMON_ARRAY_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stddef.h>
#include <stdint.h>

/// @brief Dynamic array of pointers.
typedef struct ke_array
{
    void **data;
    size_t size;
    size_t capacity;
    ke_allocator *allocator;
} ke_array;

/// @brief Initializes an array.
static inline ke_result ke_array_init(ke_array *arr, size_t initial_capacity, ke_allocator *alloc)
{
    if (!arr || !alloc)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    arr->allocator = alloc;
    arr->size = 0;
    arr->capacity = initial_capacity;
    arr->data = (void **)alloc->alloc(alloc, initial_capacity * sizeof(void *), 0);
    return arr->data ? KE_OK : KE_ERROR_OUT_OF_MEMORY;
}

/// @brief Pushes a value to the end of the array.
static inline ke_result ke_array_push(ke_array *arr, void *value)
{
    if (!arr)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    if (arr->size >= arr->capacity)
    {
        size_t new_cap = arr->capacity == 0 ? 4 : arr->capacity * 2;
        void **new_data = (void **)arr->allocator->realloc(arr->allocator, arr->data, new_cap * sizeof(void *));
        if (!new_data)
        {
            return KE_ERROR_OUT_OF_MEMORY;
        }
        arr->data = new_data;
        arr->capacity = new_cap;
    }
    arr->data[arr->size++] = value;
    return KE_OK;
}

/// @brief Destroys the array.
static inline void ke_array_destroy(ke_array *arr)
{
    if (!arr)
    {
        return;
    }
    if (arr->data && arr->allocator)
    {
        arr->allocator->free(arr->allocator, arr->data);
    }
    arr->data = NULL;
    arr->size = 0;
    arr->capacity = 0;
}

#endif // KERNEL_ENGINE_KERNEL_COMMON_ARRAY_H_
