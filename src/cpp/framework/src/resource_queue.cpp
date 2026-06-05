// Mutex-protected std::deque implementation of ke_resource_queue. The lock-free
// SPSC ring buffer is deferred; the public ABI stays unchanged so impl can be
// swapped later without touching callers.
//
// Variable-length payloads (vertex/index/pixel arrays) are copied into the
// queue's allocator on submit. Each future owns its result + condvar; release
// frees it (callers must release every future they receive).

#include <kernel_engine/framework/resource_queue.h>
#include <kernel_engine/kernel/render/render.h>

#include <condition_variable>
#include <cstring>
#include <deque>
#include <mutex>
#include <new>
#include <vector>

namespace
{

// ── Future ───────────────────────────────────────────────────────────────────

enum class FutureState : uint8_t { Pending, Ready };

struct FutureImpl
{
    std::mutex              mutex;
    std::condition_variable cv;
    FutureState             state    = FutureState::Pending;
    ke_result               result   = KE_OK;
    uint32_t                handle   = 0;
    ke_allocator           *allocator = nullptr;
};

void future_complete(FutureImpl *f, ke_result rc, uint32_t handle)
{
    {
        std::lock_guard<std::mutex> lock(f->mutex);
        f->result = rc;
        f->handle = handle;
        f->state  = FutureState::Ready;
    }
    f->cv.notify_all();
}

// ── Owned-payload copies ────────────────────────────────────────────────────
//
// The submitted command may carry pointers into transient caller buffers; we
// duplicate them onto our allocator so the renderer drain can read them after
// the caller's buffer is gone.

struct QueueEntry
{
    ke_resource_command_kind kind;
    uint32_t                 destroy_handle  = 0;
    ke_create_shadow_map_cmd shadow          = {0, 0};
    ke_material              material        = {};
    uint32_t                 width           = 0;
    uint32_t                 height          = 0;
    uint32_t                 face_size       = 0;
    uint32_t                 vertex_count    = 0;
    uint32_t                 index_count     = 0;
    uint32_t                 pixel_byte_count = 0;
    ke_vertex               *vertices        = nullptr;
    uint16_t                *indices         = nullptr;
    uint8_t                 *pixels          = nullptr;
    FutureImpl              *future          = nullptr; // optional
};

struct QueueImpl
{
    ke_resource_queue  api{};
    ke_allocator      *allocator = nullptr;
    std::mutex         mutex;
    std::deque<QueueEntry> pending;
};

void *alloc_blob(ke_allocator *a, size_t bytes, size_t align)
{
    if (bytes == 0) return nullptr;
    return a->alloc(a, bytes, align);
}

void free_entry_payload(ke_allocator *a, QueueEntry &e)
{
    if (e.vertices) a->free(a, e.vertices);
    if (e.indices)  a->free(a, e.indices);
    if (e.pixels)   a->free(a, e.pixels);
    e.vertices = nullptr; e.indices = nullptr; e.pixels = nullptr;
}

// ── vtable: submit ──────────────────────────────────────────────────────────

ke_result impl_submit(ke_resource_queue          *self,
                      const ke_resource_command  *cmd,
                      ke_resource_future        **out_future)
{
    if (!self || !self->handle || !cmd) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<QueueImpl *>(self->handle);

    QueueEntry entry;
    entry.kind = cmd->kind;

    switch (cmd->kind) {
    case KE_RESOURCE_CMD_CREATE_MESH: {
        const auto &c = cmd->u.create_mesh;
        if ((c.vertex_count > 0 && !c.vertices) ||
            (c.index_count > 0 && !c.indices)) return KE_ERROR_INVALID_ARGUMENT;
        entry.vertex_count = c.vertex_count;
        entry.index_count  = c.index_count;
        if (c.vertex_count > 0) {
            entry.vertices = static_cast<ke_vertex *>(
                alloc_blob(impl->allocator, sizeof(ke_vertex) * c.vertex_count, alignof(ke_vertex)));
            if (!entry.vertices) return KE_ERROR_OUT_OF_MEMORY;
            std::memcpy(entry.vertices, c.vertices, sizeof(ke_vertex) * c.vertex_count);
        }
        if (c.index_count > 0) {
            entry.indices = static_cast<uint16_t *>(
                alloc_blob(impl->allocator, sizeof(uint16_t) * c.index_count, alignof(uint16_t)));
            if (!entry.indices) {
                free_entry_payload(impl->allocator, entry);
                return KE_ERROR_OUT_OF_MEMORY;
            }
            std::memcpy(entry.indices, c.indices, sizeof(uint16_t) * c.index_count);
        }
        break;
    }
    case KE_RESOURCE_CMD_CREATE_TEXTURE: {
        const auto &c = cmd->u.create_texture;
        entry.width  = c.width;
        entry.height = c.height;
        size_t bytes = static_cast<size_t>(c.width) * c.height * 4;
        if (bytes > 0) {
            entry.pixels = static_cast<uint8_t *>(alloc_blob(impl->allocator, bytes, 1));
            if (!entry.pixels) return KE_ERROR_OUT_OF_MEMORY;
            std::memcpy(entry.pixels, c.pixels, bytes);
            entry.pixel_byte_count = static_cast<uint32_t>(bytes);
        }
        break;
    }
    case KE_RESOURCE_CMD_CREATE_CUBEMAP: {
        const auto &c = cmd->u.create_cubemap;
        entry.face_size = c.face_size;
        size_t bytes = static_cast<size_t>(c.face_size) * c.face_size * 4 * 6;
        if (bytes > 0) {
            entry.pixels = static_cast<uint8_t *>(alloc_blob(impl->allocator, bytes, 1));
            if (!entry.pixels) return KE_ERROR_OUT_OF_MEMORY;
            std::memcpy(entry.pixels, c.pixels, bytes);
            entry.pixel_byte_count = static_cast<uint32_t>(bytes);
        }
        break;
    }
    case KE_RESOURCE_CMD_CREATE_MATERIAL:
        entry.material = cmd->u.create_material.material;
        break;
    case KE_RESOURCE_CMD_CREATE_SHADOW_MAP:
        entry.shadow = cmd->u.create_shadow_map;
        break;
    case KE_RESOURCE_CMD_DESTROY_MESH:
    case KE_RESOURCE_CMD_DESTROY_TEXTURE:
    case KE_RESOURCE_CMD_DESTROY_MATERIAL:
    case KE_RESOURCE_CMD_DESTROY_SHADOW_MAP:
        entry.destroy_handle = cmd->u.destroy.handle;
        break;
    default:
        return KE_ERROR_INVALID_ARGUMENT;
    }

    if (out_future) {
        void *mem = impl->allocator->alloc(impl->allocator, sizeof(FutureImpl), alignof(FutureImpl));
        if (!mem) {
            free_entry_payload(impl->allocator, entry);
            return KE_ERROR_OUT_OF_MEMORY;
        }
        auto *fut = new (mem) FutureImpl();
        fut->allocator = impl->allocator;
        entry.future = fut;
        *out_future  = reinterpret_cast<ke_resource_future *>(fut);
    }

    {
        std::lock_guard<std::mutex> lock(impl->mutex);
        impl->pending.push_back(std::move(entry));
    }
    return KE_OK;
}

// ── vtable: drain ───────────────────────────────────────────────────────────

uint32_t impl_drain(ke_resource_queue *self, ke_render *renderer, uint32_t max_count)
{
    if (!self || !self->handle || !renderer) return 0;
    auto *impl = static_cast<QueueImpl *>(self->handle);

    // Move pending entries out under the lock; execute outside so renderer
    // calls don't hold the queue mutex (avoids re-entrancy if a renderer call
    // ever submits more commands).
    std::vector<QueueEntry> batch;
    {
        std::lock_guard<std::mutex> lock(impl->mutex);
        uint32_t take = max_count == 0
            ? static_cast<uint32_t>(impl->pending.size())
            : (max_count < impl->pending.size() ? max_count : static_cast<uint32_t>(impl->pending.size()));
        batch.reserve(take);
        for (uint32_t i = 0; i < take; ++i) {
            batch.push_back(std::move(impl->pending.front()));
            impl->pending.pop_front();
        }
    }

    for (auto &e : batch) {
        ke_result rc = KE_OK;
        uint32_t  handle = 0;
        switch (e.kind) {
        case KE_RESOURCE_CMD_CREATE_MESH: {
            ke_mesh_handle h{};
            rc = renderer->create_mesh(renderer, e.vertices, e.vertex_count, e.indices, e.index_count, &h);
            handle = h.idx;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_TEXTURE: {
            ke_texture_handle h{};
            rc = renderer->create_texture_rgba(renderer, e.width, e.height, e.pixels, &h);
            handle = h.idx;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_CUBEMAP: {
            ke_texture_handle h{};
            rc = renderer->create_cubemap_rgba(renderer, e.face_size, e.pixels, &h);
            handle = h.idx;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_MATERIAL: {
            ke_material_handle h{};
            rc = renderer->create_material(renderer, &e.material, &h);
            handle = h.idx;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_SHADOW_MAP: {
            ke_shadow_map_handle h{};
            rc = renderer->create_shadow_map(renderer, e.shadow.width, e.shadow.height, &h);
            handle = h.idx;
            break;
        }
        case KE_RESOURCE_CMD_DESTROY_MESH:
            rc = renderer->destroy_mesh(renderer, ke_mesh_handle{e.destroy_handle});
            break;
        case KE_RESOURCE_CMD_DESTROY_TEXTURE:
            rc = renderer->destroy_texture(renderer, ke_texture_handle{e.destroy_handle});
            break;
        case KE_RESOURCE_CMD_DESTROY_MATERIAL:
            rc = renderer->destroy_material(renderer, ke_material_handle{e.destroy_handle});
            break;
        case KE_RESOURCE_CMD_DESTROY_SHADOW_MAP:
            rc = renderer->destroy_shadow_map(renderer, ke_shadow_map_handle{e.destroy_handle});
            break;
        }

        if (e.future) future_complete(e.future, rc, handle);
        free_entry_payload(impl->allocator, e);
    }
    return static_cast<uint32_t>(batch.size());
}

// ── vtable: destroy ─────────────────────────────────────────────────────────

void impl_destroy(ke_resource_queue *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<QueueImpl *>(self->handle);
    // Cancel any pending entries: signal futures with KE_ERROR so waiters wake up.
    {
        std::lock_guard<std::mutex> lock(impl->mutex);
        for (auto &e : impl->pending) {
            if (e.future) future_complete(e.future, KE_ERROR, 0);
            free_entry_payload(impl->allocator, e);
        }
        impl->pending.clear();
    }
    ke_allocator *alloc = impl->allocator;
    impl->~QueueImpl();
    alloc->free(alloc, impl);
}

} // namespace

// ── Future API ──────────────────────────────────────────────────────────────

extern "C" ke_result ke_resource_future_wait(ke_resource_future *future, uint32_t timeout_ms)
{
    if (!future) return KE_ERROR_INVALID_ARGUMENT;
    auto *f = reinterpret_cast<FutureImpl *>(future);
    std::unique_lock<std::mutex> lock(f->mutex);
    if (f->state == FutureState::Ready) return f->result;
    if (timeout_ms == 0) return KE_ERROR_INVALID_ARGUMENT;
    if (timeout_ms == UINT32_MAX) {
        f->cv.wait(lock, [&]{ return f->state == FutureState::Ready; });
    } else {
        f->cv.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                       [&]{ return f->state == FutureState::Ready; });
        if (f->state != FutureState::Ready) return KE_ERROR_INVALID_ARGUMENT;
    }
    return f->result;
}

extern "C" uint32_t ke_resource_future_get_handle(ke_resource_future *future)
{
    if (!future) return 0;
    auto *f = reinterpret_cast<FutureImpl *>(future);
    std::lock_guard<std::mutex> lock(f->mutex);
    return f->handle;
}

extern "C" void ke_resource_future_release(ke_resource_future *future)
{
    if (!future) return;
    auto *f = reinterpret_cast<FutureImpl *>(future);
    ke_allocator *a = f->allocator;
    f->~FutureImpl();
    a->free(a, f);
}

// ── Factory ─────────────────────────────────────────────────────────────────

extern "C" ke_result ke_resource_queue_create(ke_allocator *alloc, ke_resource_queue **out)
{
    if (!alloc || !out) return KE_ERROR_INVALID_ARGUMENT;
    void *mem = alloc->alloc(alloc, sizeof(QueueImpl), alignof(QueueImpl));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;
    auto *impl = new (mem) QueueImpl();
    impl->allocator   = alloc;
    impl->api.handle  = impl;
    impl->api.submit  = impl_submit;
    impl->api.drain   = impl_drain;
    impl->api.destroy = impl_destroy;
    *out = &impl->api;
    return KE_OK;
}
