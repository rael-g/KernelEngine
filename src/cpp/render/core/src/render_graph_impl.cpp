#include "render_graph_impl.hpp"
#include "core_renderer.hpp"
#include "render_logging.hpp"
#include <gpu_device.hpp>

#include <algorithm>
#include <cstring>
#include <new>
#include <unordered_set>

namespace kernel_engine::render::core
{

thread_local RenderGraphImpl::Bridge RenderGraphImpl::tls_bridge_;

namespace {

// Maps the cross-backend ke_resource_format → bgfx-style format constant the
// GpuDevice already understands. Kept private to this TU because the contract
// is defined by what GpuDevice::CreateTexture2D accepts.
uint32_t MapFormat(ke_resource_format fmt, bool& out_is_depth)
{
    out_is_depth = false;
    switch (fmt) {
        case KE_FORMAT_RGBA8_UNORM: return kTexFmtRGBA8;
        case KE_FORMAT_RGBA16F:     return kTexFmtRGBA16F;
        case KE_FORMAT_R32F:        return kTexFmtR32F;
        case KE_FORMAT_D16:         out_is_depth = true; return kTexFmtD16;
        // D24S8 and D32F not yet exposed through GpuDevice's constant set; reject
        // at compile-time below until a backer adds them (failure surfaces synchronously
        // rather than producing a silently-wrong format choice).
        case KE_FORMAT_D24S8:
        case KE_FORMAT_D32F:
        case KE_FORMAT_UNDEFINED:
        default:                    return UINT32_MAX;
    }
}

bool AccessIsWrite(ke_resource_access a)
{
    return a == KE_ACCESS_COLOR_ATTACHMENT
        || a == KE_ACCESS_DEPTH_ATTACHMENT
        || a == KE_ACCESS_STORAGE_WRITE
        || a == KE_ACCESS_STORAGE_RW;
}

} // namespace

// ── ctor / dtor / vtable ─────────────────────────────────────────────────

RenderGraphImpl::RenderGraphImpl(CoreRenderer* renderer, ke_allocator* allocator)
    : renderer_(renderer)
    , allocator_(allocator)
{
    std::memset(&api_, 0, sizeof(api_));
    api_.handle = this;

    api_.destroy = [](ke_render_graph* self) {
        if (!self || !self->handle) return;
        auto* impl = static_cast<RenderGraphImpl*>(self->handle);
        auto* alloc = impl->allocator_;
        impl->~RenderGraphImpl();
        if (alloc) alloc->free(alloc, impl);
    };

    api_.declare_resource = [](ke_render_graph* self, const ke_resource_desc* desc) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->DeclareResource(desc);
    };
    api_.import_texture = [](ke_render_graph* self, const char* name, ke_texture_handle handle) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->ImportTexture(name, handle);
    };
    api_.add_pass = [](ke_render_graph* self, const ke_render_pass_params* params) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->AddPass(params);
    };
    api_.remove_pass = [](ke_render_graph* self, const char* name) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->RemovePass(name);
    };
    api_.compile = [](ke_render_graph* self) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->Compile();
    };
    api_.execute = [](ke_render_graph* self, const ke_frame_packet* packet) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        return static_cast<RenderGraphImpl*>(self->handle)->Execute(packet);
    };
}

RenderGraphImpl::~RenderGraphImpl()
{
    ReleaseAllResources();
}

ke_render_graph* RenderGraphImpl::ToApi()
{
    return &api_;
}

// ── DeclareResource ──────────────────────────────────────────────────────

ke_result RenderGraphImpl::DeclareResource(const ke_resource_desc* desc)
{
    if (!desc || !desc->name || desc->name[0] == '\0')
        return KE_ERROR_INVALID_ARGUMENT;

    if (resources_.find(desc->name) != resources_.end()) {
        // Re-declaring is a programming error — two unrelated systems would
        // step on each other if we silently accepted.
        return KE_ERROR_ALREADY_EXISTS;
    }

    Resource r{};
    r.name = desc->name;
    r.desc = *desc;
    // Name lives in the map key + r.name — null out the borrowed pointer in the
    // copied desc so nobody reads a dangling string later.
    r.desc.name = nullptr;
    r.is_imported = false;

    resources_.emplace(r.name, std::move(r));
    dirty_ = true;
    return KE_OK;
}

ke_result RenderGraphImpl::ImportTexture(const char* name, ke_texture_handle handle)
{
    if (!name || name[0] == '\0')
        return KE_ERROR_INVALID_ARGUMENT;

    if (resources_.find(name) != resources_.end())
        return KE_ERROR_ALREADY_EXISTS;

    Resource r{};
    r.name = name;
    r.is_imported = true;
    // Store the imported kernel-level handle as-is. get_texture returns it
    // verbatim. Transient textures (graph-allocated) currently expose only
    // the backend GpuTextureHandle to in-process record callbacks; Phase 5
    // wires kernel-handle aliasing through TextureManager.
    r.imported_handle = handle;
    r.texture = kGpuInvalidHandle;
    r.framebuffer = kGpuInvalidHandle;
    r.owns_texture = false;
    r.owns_framebuffer = false;

    resources_.emplace(r.name, std::move(r));
    dirty_ = true;
    return KE_OK;
}

// ── AddPass / RemovePass ─────────────────────────────────────────────────

ke_result RenderGraphImpl::AddPass(const ke_render_pass_params* params)
{
    if (!params || !params->name || params->name[0] == '\0' || !params->record)
        return KE_ERROR_INVALID_ARGUMENT;

    // Duplicate pass name = ambiguity at remove time.
    for (const auto& p : passes_) {
        if (p.name == params->name) return KE_ERROR_ALREADY_EXISTS;
    }

    Pass pass{};
    pass.name = params->name;
    pass.type = params->type;
    pass.record = params->record;
    pass.user = params->user;

    pass.reads.reserve(params->reads_count);
    for (uint32_t i = 0; i < params->reads_count; ++i) {
        const auto& src = params->reads[i];
        if (!src.name) return KE_ERROR_INVALID_ARGUMENT;
        pass.reads.push_back({ src.name, src.access });
    }

    pass.writes.reserve(params->writes_count);
    for (uint32_t i = 0; i < params->writes_count; ++i) {
        const auto& src = params->writes[i];
        if (!src.name) return KE_ERROR_INVALID_ARGUMENT;
        pass.writes.push_back({ src.name, src.access });
    }

    passes_.push_back(std::move(pass));
    dirty_ = true;
    return KE_OK;
}

ke_result RenderGraphImpl::RemovePass(const char* name)
{
    if (!name) return KE_ERROR_INVALID_ARGUMENT;
    auto it = std::find_if(passes_.begin(), passes_.end(),
        [&](const Pass& p) { return p.name == name; });
    if (it == passes_.end()) return KE_ERROR_NOT_FOUND;
    passes_.erase(it);
    dirty_ = true;
    return KE_OK;
}

// ── Compile (topo-sort + materialize transients + assign view-ids) ──────

ke_result RenderGraphImpl::Compile()
{
    if (!dirty_) return KE_OK;

    // 1. Validate: every read/write resource must be declared.
    for (const auto& pass : passes_) {
        for (const auto& r : pass.reads) {
            if (resources_.find(r.name) == resources_.end())
                return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_NOT_FOUND,
                    "RenderGraph.Compile",
                    "Pass references an undeclared resource (see logs for name).");
        }
        for (const auto& w : pass.writes) {
            if (resources_.find(w.name) == resources_.end())
                return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_NOT_FOUND,
                    "RenderGraph.Compile",
                    "Pass writes an undeclared resource (see logs for name).");
            if (!AccessIsWrite(w.access))
                return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_INVALID_ARGUMENT,
                    "RenderGraph.Compile",
                    "Pass declares a resource under 'writes' but the access is read-only.");
        }
        // Compute pass acceptance landed in Phase 4.1; the per-pass record
        // callback is responsible for the actual dispatch (the executor only
        // schedules the view-id slot the pass should run under).
    }

    // 2. Producer map: which pass writes each resource? Two writers = error.
    std::unordered_map<std::string, size_t> producer;
    for (size_t i = 0; i < passes_.size(); ++i) {
        for (const auto& w : passes_[i].writes) {
            auto result = producer.emplace(w.name, i);
            if (!result.second) {
                return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_INVALID_ARGUMENT,
                    "RenderGraph.Compile",
                    "Two passes write the same resource — split into distinct resources or merge passes.");
            }
        }
    }

    // 3. Adjacency + in-degree for Kahn's algorithm.
    std::vector<std::vector<size_t>> edges(passes_.size());
    std::vector<size_t> in_degree(passes_.size(), 0);
    for (size_t i = 0; i < passes_.size(); ++i) {
        for (const auto& r : passes_[i].reads) {
            auto it = producer.find(r.name);
            if (it == producer.end()) continue; // imported / externally produced — no edge
            size_t from = it->second;
            if (from == i) continue;             // self-read tolerated (in-place RW)
            edges[from].push_back(i);
            in_degree[i] += 1;
        }
    }

    // 4. Kahn — declaration order is the tiebreaker so the user has a knob.
    std::vector<size_t> order;
    order.reserve(passes_.size());
    std::vector<size_t> ready;
    for (size_t i = 0; i < passes_.size(); ++i)
        if (in_degree[i] == 0) ready.push_back(i);

    while (!ready.empty()) {
        size_t i = ready.front();
        ready.erase(ready.begin());
        order.push_back(i);
        for (size_t j : edges[i]) {
            if (--in_degree[j] == 0) ready.push_back(j);
        }
    }
    if (order.size() != passes_.size()) {
        return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_INVALID_ARGUMENT,
            "RenderGraph.Compile",
            "Resource dependency cycle detected — split shared resources.");
    }

    execution_order_ = std::move(order);

    // 5. Materialize transient resources, assign sequential view-ids.
    // The view-id base offset (base_view_id_) avoids colliding with the legacy
    // hard-coded view chain that Phase 3 will retire; once migration is done
    // the offset drops to 0.
    for (size_t step = 0; step < execution_order_.size(); ++step) {
        Pass& pass = passes_[execution_order_[step]];
        pass.view_id = static_cast<uint16_t>(base_view_id_ + step);

        // Pick a target framebuffer from the writes — first color or depth
        // attachment found. MRT will require collecting multiple textures.
        pass.target_fb = kGpuInvalidHandle;
        for (const auto& w : pass.writes) {
            Resource* res = FindResource(w.name);
            if (!res) continue;
            // Imported "backbuffer" reads as kGpuInvalidHandle framebuffer —
            // bgfx treats that as "render to default backbuffer". Convenient
            // and intentional.
            if (res->is_imported && res->name == "backbuffer") continue;

            ke_result ok = EnsureResourceMaterialized(*res);
            if (ok != KE_OK) return ok;
            if (res->framebuffer != kGpuInvalidHandle) {
                pass.target_fb = res->framebuffer;
                break;
            }
        }
    }

    dirty_ = false;
    return KE_OK;
}

ke_result RenderGraphImpl::EnsureResourceMaterialized(Resource& r)
{
    if (r.is_imported) return KE_OK; // caller's texture, nothing to allocate.

    GpuDevice* gpu = renderer_->GetContext().gpu;
    if (!gpu) return KE_ERROR_NOT_INITIALIZED;

    if (r.desc.type == KE_RESOURCE_TYPE_STORAGE_BUFFER) {
        if (r.storage_buffer != kGpuInvalidHandle) return KE_OK;
        if (r.desc.element_count == 0 || r.desc.element_stride == 0)
            return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_INVALID_ARGUMENT,
                "RenderGraph.Compile",
                "Storage buffer resource requires non-zero element_count and element_stride.");
        // bgfx represents compute-rw storage buffers as dynamic index buffers
        // tagged BGFX_BUFFER_COMPUTE_READ_WRITE (0x0c00 when truncated to the
        // 16-bit flag word). Element stride is encoded by the buffer type —
        // index32 = 4 bytes; tighter packing comes when the contract adds a
        // dedicated storage-buffer creation path.
        const uint16_t kComputeReadWrite = 0x0C00;
        uint32_t total_words = r.desc.element_count;
        if (r.desc.element_stride > 4)
            total_words = (r.desc.element_count * r.desc.element_stride + 3) / 4;
        r.storage_buffer = gpu->CreateDynamicIndexBuffer(total_words, kComputeReadWrite);
        r.owns_storage_buffer = r.storage_buffer != kGpuInvalidHandle;
        return r.storage_buffer != kGpuInvalidHandle ? KE_OK : KE_ERROR_RENDER;
    }

    if (r.texture != kGpuInvalidHandle) return KE_OK; // already done.

    bool is_depth = false;
    uint32_t fmt = MapFormat(r.desc.format, is_depth);
    if (fmt == UINT32_MAX)
        return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_INVALID_ARGUMENT,
            "RenderGraph.Compile",
            "Backend does not yet support the requested ke_resource_format.");

    // Resolve absolute size.
    uint32_t w = r.desc.width;
    uint32_t h = r.desc.height;
    if (r.desc.size_mode == KE_SIZE_RELATIVE_TO_BACKBUFFER) {
        // TODO: route through the renderer's known backbuffer size. For now
        // we reject relative sizing until we plumb that through — phase-3
        // migrations (bloom half-res) will need it.
        return KE_RENDER_LOG_ERR(renderer_->GetContext().logger, KE_ERROR_NOT_SUPPORTED,
            "RenderGraph.Compile",
            "KE_SIZE_RELATIVE_TO_BACKBUFFER not yet wired — pass absolute width/height for now.");
    }

    r.texture = gpu->CreateTexture2D(
        static_cast<uint16_t>(w), static_cast<uint16_t>(h),
        /*hasMips*/false, /*numLayers*/1, fmt, kTexFlagRT, nullptr);
    r.owns_texture = true;

    if (r.texture == kGpuInvalidHandle)
        return KE_ERROR_RENDER;

    // One-texture framebuffer for now (color OR depth target). MRT later.
    GpuTextureHandle attachments[1] = { r.texture };
    r.framebuffer = gpu->CreateFrameBuffer(1, attachments, /*destroyTextures*/false);
    r.owns_framebuffer = r.framebuffer != kGpuInvalidHandle;
    return KE_OK;
}

ke_result RenderGraphImpl::ReleaseAllResources()
{
    GpuDevice* gpu = renderer_ ? renderer_->GetContext().gpu : nullptr;
    if (gpu) {
        for (auto& [name, r] : resources_) {
            if (r.owns_framebuffer)     gpu->DestroyFrameBuffer(r.framebuffer);
            if (r.owns_texture)         gpu->DestroyTexture(r.texture);
            if (r.owns_storage_buffer)  gpu->DestroyDynamicIndexBuffer(r.storage_buffer);
            r.framebuffer = kGpuInvalidHandle;
            r.texture = kGpuInvalidHandle;
            r.storage_buffer = kGpuInvalidHandle;
            r.owns_framebuffer = false;
            r.owns_texture = false;
            r.owns_storage_buffer = false;
        }
    }
    return KE_OK;
}

// ── Execute ──────────────────────────────────────────────────────────────

ke_render_pass_ctx RenderGraphImpl::BuildPassCtx(Pass& pass)
{
    // The bridge lives in TLS for the duration of the record callback. It is
    // populated freshly per pass per frame, so concurrent graph execution on
    // different threads stays isolated (each thread owns its own slot).
    auto& b = tls_bridge_;
    b.impl = this;
    b.pass = &pass;
    b.packet = nullptr; // patched in Execute right before the callback fires.

    ke_render_pass_ctx ctx{};
    ctx.handle = &b;
    ctx.get_texture = [](ke_render_pass_ctx* self, const char* name) -> ke_texture_handle {
        ke_texture_handle none{ UINT32_MAX };
        if (!self || !self->handle || !name) return none;
        auto* br = static_cast<Bridge*>(self->handle);
        auto allowed = [&](const std::vector<ResourceRefOwned>& list) {
            for (const auto& r : list) if (r.name == name) return true;
            return false;
        };
        if (!allowed(br->pass->reads) && !allowed(br->pass->writes)) return none;
        auto* r = br->impl->FindResource(name);
        if (!r) return none;
        if (r->is_imported) return r->imported_handle;
        // Transient textures don't have a TextureManager-registered kernel
        // handle yet (Phase 5). Expose the raw backend id as a uint32_t so
        // in-process record callbacks that go through GpuDevice can still
        // bind it; external user code that expects a true kernel handle
        // gets KE_HANDLE_NONE until aliasing lands.
        ke_texture_handle h{ static_cast<uint32_t>(r->texture) };
        return h;
    };
    ctx.get_backbuffer_size = [](ke_render_pass_ctx* self, uint32_t* out_w, uint32_t* out_h) {
        if (!self || !self->handle) return;
        auto* br = static_cast<Bridge*>(self->handle);
        br->impl->renderer_->GetBackbufferSize(out_w, out_h);
    };
    ctx.get_frame_packet = [](ke_render_pass_ctx* self) -> const ke_frame_packet* {
        if (!self || !self->handle) return nullptr;
        return static_cast<Bridge*>(self->handle)->packet;
    };
    ctx.get_renderer = [](ke_render_pass_ctx* self) -> ke_render* {
        if (!self || !self->handle) return nullptr;
        return static_cast<Bridge*>(self->handle)->impl->renderer_->ToApi();
    };
    return ctx;
}

ke_result RenderGraphImpl::Execute(const ke_frame_packet* packet)
{
    if (dirty_) {
        ke_result rc = Compile();
        if (rc != KE_OK) return rc;
    }

    GpuDevice* gpu = renderer_->GetContext().gpu;
    if (!gpu) return KE_ERROR_NOT_INITIALIZED;

    for (size_t idx : execution_order_) {
        Pass& pass = passes_[idx];

        // Bind the pass's target framebuffer. INVALID handle = backbuffer.
        gpu->SetViewFrameBuffer(pass.view_id, pass.target_fb);
        gpu->Touch(pass.view_id);

        ke_render_pass_ctx ctx = BuildPassCtx(pass);
        tls_bridge_.packet = packet;

        pass.record(&ctx, pass.user);
    }
    return KE_OK;
}

// ── helpers ──────────────────────────────────────────────────────────────

RenderGraphImpl::Resource* RenderGraphImpl::FindResource(const std::string& name)
{
    auto it = resources_.find(name);
    return it == resources_.end() ? nullptr : &it->second;
}

} // namespace kernel_engine::render::core
