#ifndef KERNEL_ENGINE_FRAMEWORK_SIGNAL_BUS_H_
#define KERNEL_ENGINE_FRAMEWORK_SIGNAL_BUS_H_

#include <stdbool.h>
#include <stdint.h>

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Routes one node's emission to the nodes connected to it, splitting the two
    /// lifetimes a signal has.
    ///
    /// An emission is a single frame's event: queued while systems run, joined
    /// against the connection table once, readable until the next frame clears it.
    /// A connection is durable and language-neutral — it names a target entity and
    /// a handler, never a closure in one runtime's heap — so a node authored in one
    /// language can be wired to a signal a node in another language raises.
    ///
    /// The join is what keeps an emitter from knowing its listeners: a node calls
    /// emit against its own entity, and who receives that is a fact of the scene,
    /// changeable without touching either node.
    typedef struct ke_signal_bus ke_signal_bus;

/// Passed as the payload size by a caller that only needs the signal's id and
/// does not know its layout — a scene file wiring two nodes together names the
/// signal but has no way to know how many bytes it carries. The size stays
/// unknown until whoever owns the payload type declares it, and only then does
/// a conflicting declaration become an error.
#define KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN 0xFFFFFFFFu

    /// One delivery of one emission to one connected target.
    /// The payload points into the bus's frame storage and is valid until the
    /// frame is cleared; a consumer that needs it longer copies it.
    typedef struct ke_signal_delivery
    {
        ke_entity   source;       ///< Entity that emitted.
        ke_entity   target;       ///< Entity connected to it.
        uint32_t    signal_id;    ///< Which signal, as resolved by signal_id().
        uint32_t    handler_id;   ///< Handler selector the connection recorded.
        const void *payload;      ///< Emission payload, borrowed for the frame.
        uint32_t    payload_size; ///< Payload length in bytes.
    } ke_signal_delivery;

    struct ke_signal_bus
    {
        void *handle;

        /// [interns] Resolves a signal by name, registering it on first use.
        ///
        /// The payload size is part of the identity, not metadata: two languages
        /// naming the same signal with different payload layouts would otherwise
        /// alias one id and read each other's bytes at the wrong stride. A second
        /// registration under a different size fails instead.
        /// @param name [utf8, type_name]
        /// @param payload_size [type_size]
        /// @param out_id [out]
        bool (*signal_id)(struct ke_signal_bus *self,
                          const char           *name,
                          uint32_t              payload_size,
                          uint32_t             *out_id,
                          ke_error            **out_error);

        /// [try] Resolves a signal by name without registering it, so a caller that
        /// did not author the name can tell an existing signal from a typo. A scene
        /// file is exactly that caller: signal_id would happily invent the signal
        /// its author misspelled, and the connection would then never fire.
        /// @param name [utf8]
        /// @param out_id [out]
        bool (*signal_lookup)(struct ke_signal_bus *self,
                              const char           *name,
                              uint32_t             *out_id);

        /// Wires one source entity's signal to one target entity, tagged with a
        /// handler selector the receiving language interprets. Connecting the same
        /// quadruple twice is a no-op rather than a duplicate delivery.
        bool (*connect)(struct ke_signal_bus *self,
                        ke_entity             source,
                        uint32_t              signal_id,
                        ke_entity             target,
                        uint32_t              handler_id,
                        ke_error            **out_error);

        /// Removes a connection previously made by connect(). Returns false when
        /// no such connection exists.
        bool (*disconnect)(struct ke_signal_bus *self,
                           ke_entity             source,
                           uint32_t              signal_id,
                           ke_entity             target,
                           uint32_t              handler_id);

        /// Drops every connection naming this entity as source or target, so a
        /// destroyed node cannot be delivered to or emit through a stale wire.
        void (*forget_entity)(struct ke_signal_bus *self, ke_entity entity);

        /// Queues one emission for this frame. The payload is copied into frame
        /// storage, so the caller's buffer need not outlive the call.
        bool (*emit)(struct ke_signal_bus *self,
                     ke_entity             source,
                     uint32_t              signal_id,
                     const void           *payload,
                     uint32_t              payload_size,
                     ke_error            **out_error);

        /// Joins this frame's emissions against the connection table and returns
        /// the resulting deliveries. Idempotent within a frame: calling it twice
        /// returns the same list rather than duplicating it.
        /// @param out_count [out]
        /// @return [array_of:out_count]
        const ke_signal_delivery *(*deliveries)(struct ke_signal_bus *self, uint32_t *out_count);

        /// Discards this frame's emissions and deliveries. Connections survive.
        void (*clear_frame)(struct ke_signal_bus *self);
    };

    /// Owner wrapper: destroy releases the connection table and frame storage.
    typedef struct ke_signal_bus_handle
    {
        ke_signal_bus *ref;
        void (*destroy)(ke_signal_bus *self);
    } ke_signal_bus_handle;

#ifdef __cplusplus
}
#endif

#endif
