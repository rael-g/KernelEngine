#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_system_ctx ke_system_ctx;

/// What one call of a system body is given to work with: the entities its queries
/// resolved to, which share of them it owns, and the queue it records structural changes
/// into. It exists for the duration of the call and means nothing outside it. `handle` is
/// runtime-private.
struct ke_system_ctx {
    void *handle;

    /// The queue this body records structural changes into, applied at the wave barrier.
    /// In the render phase the queue refuses every operation, because that phase reads an
    /// extracted snapshot and may not change structure.
    ke_ecs_commands *commands;

    /// The system body's only path to component memory. Returns the resolved archetype
    /// segments for the system's query at query_index (the order the queries were
    /// declared in ke_runtime_system_params). Sets *out_count to the segment count and
    /// returns the segment array; both are valid for the duration of the system body.
    /// Makes no ke_ecs call: the segments were resolved single-threaded before the wave,
    /// because an ECS iterator allocates from storage shared across the wave's parallel
    /// systems. Returns NULL for an out-of-range index or a system that declared no
    /// queries.
    /// @param out_count [out]
    /// @return [array_of:out_count]
    const ke_ecs_segment *(*view)(ke_system_ctx *self, uint32_t query_index, size_t *out_count);

    /// Reports which share of its entity set this body call owns: *out_index in
    /// [0, *out_count). A system that did not declare per_entity always gets index 0 of
    /// count 1, so a body written against this reads the whole set without asking
    /// whether it was sliced.
    /// @param out_index [out]
    /// @param out_count [out]
    void (*slice)(ke_system_ctx *self, uint32_t *out_index, uint32_t *out_count);
};

#ifdef __cplusplus
}
#endif
