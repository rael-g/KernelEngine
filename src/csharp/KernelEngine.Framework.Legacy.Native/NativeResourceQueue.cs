using System.Collections.Concurrent;
using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Framework.Legacy.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// <see cref="IResourceCommandQueue"/> backed by the native <c>ke_resource_queue</c> plugin.
/// All ordering, payload copying, and future signaling lives in C; this wrapper only marshals
/// managed buffers across the ABI and bridges native futures to <see cref="TaskCompletionSource{TResult}"/>.
/// </summary>
internal sealed unsafe class NativeResourceQueue : IResourceCommandQueue, IDisposable
{
    private ke_resource_queue* _native;
    private readonly Allocator _allocator;

    // FIFO of futures awaiting their drain. The native queue dispatches in submit order,
    // so popping the matching count after drain pairs each future with its result.
    private readonly ConcurrentQueue<PendingFuture> _pending = new();

    private readonly record struct PendingFuture(IntPtr Future, TaskCompletionSource<uint> Tcs);

    public NativeResourceQueue(Allocator allocator)
    {
        _allocator = allocator;
        ke_resource_queue* p;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Legacy.Native.NativeMethods.resource_queue_create(allocator.Native, &p).ToManaged());
        _native = p;
    }

    public IResourceFactory CreateFactory() => new Factory(this);

    public void Drain(IRenderer renderer)
    {
        // Renderer.Native is the ke_render* — cross-cast across Kernel.Native and Framework.Native
        // generated type identities (both reference the same C struct). A non-concrete IRenderer
        // (test mocks, custom impls) cannot expose the native ptr — drain is then a no-op.
        if (renderer is not Renderer r) return;
        var rendererNative = (KernelEngine.Framework.Legacy.Native.ke_render*)r.Native;
        uint drained = _native->drain(_native, rendererNative, 0);

        // Complete the corresponding futures in submit order.
        for (uint i = 0; i < drained; i++)
        {
            if (!_pending.TryDequeue(out var entry)) break;
            var f = (ke_resource_future*)entry.Future;
            var rc = KernelEngine.Framework.Legacy.Native.NativeMethods.resource_future_wait(f, uint.MaxValue);
            if (rc == ke_result.KE_OK)
            {
                uint handle = KernelEngine.Framework.Legacy.Native.NativeMethods.resource_future_get_handle(f);
                entry.Tcs.TrySetResult(handle);
            }
            else
            {
                entry.Tcs.TrySetException(new KernelException(rc.ToManaged(), "Resource command failed"));
            }
            KernelEngine.Framework.Legacy.Native.NativeMethods.resource_future_release(f);
        }
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            // Destroying the queue cancels pending futures (native side signals KE_ERROR);
            // wake every still-pending TCS so callers don't hang.
            _native->destroy(_native);
            _native = null;
            while (_pending.TryDequeue(out var entry))
            {
                entry.Tcs.TrySetCanceled();
                KernelEngine.Framework.Legacy.Native.NativeMethods.resource_future_release(
                    (ke_resource_future*)entry.Future);
            }
        }
    }

    // ── Submit helpers ───────────────────────────────────────────────────────

    private Task<uint> SubmitCreate(ke_resource_command cmd)
    {
        var tcs = new TaskCompletionSource<uint>(TaskCreationOptions.RunContinuationsAsynchronously);
        ke_resource_future* fut;
        var rc = _native->submit(_native, &cmd, &fut);
        if (rc != ke_result.KE_OK)
        {
            tcs.SetException(new KernelException(rc.ToManaged(), "Resource submit failed"));
            return tcs.Task;
        }
        _pending.Enqueue(new PendingFuture((IntPtr)fut, tcs));
        return tcs.Task;
    }

    private void SubmitDestroy(ke_resource_command cmd)
    {
        ke_resource_future* none = null;
        var rc = _native->submit(_native, &cmd, &none);
        if (rc != ke_result.KE_OK)
            throw new KernelException(rc.ToManaged(), "Resource submit failed");
    }

    // ── Factory ──────────────────────────────────────────────────────────────

    private sealed class Factory : IResourceFactory, IAsyncResourceFactory
    {
        private readonly NativeResourceQueue _q;
        internal Factory(NativeResourceQueue q) { _q = q; }

        public Task<MeshHandle> CreateMeshAsync(Vertex[] vertices, ushort[] indices)
        {
            fixed (Vertex *vptr = vertices)
            fixed (ushort *iptr = indices)
            {
                var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_CREATE_MESH };
                cmd.u.create_mesh.vertices     = (KernelEngine.Framework.Legacy.Native.ke_vertex*)vptr;
                cmd.u.create_mesh.vertex_count = (uint)vertices.Length;
                cmd.u.create_mesh.indices      = iptr;
                cmd.u.create_mesh.index_count  = (uint)indices.Length;
                return _q.SubmitCreate(cmd).ContinueWith(t => new MeshHandle(t.Result),
                    TaskContinuationOptions.ExecuteSynchronously);
            }
        }

        public MeshHandle CreateMesh(Vertex[] vertices, ushort[] indices) =>
            CreateMeshAsync(vertices, indices).GetAwaiter().GetResult();

        public void DestroyMesh(MeshHandle handle)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_DESTROY_MESH };
            cmd.u.destroy.handle = handle.Value;
            _q.SubmitDestroy(cmd);
        }

        public Task<TextureHandle> CreateTextureAsync(uint width, uint height, byte[] pixels)
        {
            fixed (byte *p = pixels)
            {
                var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_CREATE_TEXTURE };
                cmd.u.create_texture.width  = width;
                cmd.u.create_texture.height = height;
                cmd.u.create_texture.pixels = p;
                return _q.SubmitCreate(cmd).ContinueWith(t => new TextureHandle(t.Result),
                    TaskContinuationOptions.ExecuteSynchronously);
            }
        }

        public TextureHandle CreateTexture(uint width, uint height, byte[] pixels) =>
            CreateTextureAsync(width, height, pixels).GetAwaiter().GetResult();

        public Task<TextureHandle> CreateCubemapAsync(uint faceSize, byte[] data)
        {
            fixed (byte *p = data)
            {
                var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_CREATE_CUBEMAP };
                cmd.u.create_cubemap.face_size = faceSize;
                cmd.u.create_cubemap.pixels    = p;
                return _q.SubmitCreate(cmd).ContinueWith(t => new TextureHandle(t.Result),
                    TaskContinuationOptions.ExecuteSynchronously);
            }
        }

        public TextureHandle CreateCubemap(uint faceSize, byte[] data) =>
            CreateCubemapAsync(faceSize, data).GetAwaiter().GetResult();

        public void DestroyTexture(TextureHandle handle)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_DESTROY_TEXTURE };
            cmd.u.destroy.handle = handle.Value;
            _q.SubmitDestroy(cmd);
        }

        public Task<MaterialHandle> CreateMaterialAsync(Vector4 color, TextureHandle albedo,
                                                         float metallic, float roughness,
                                                         TextureHandle normalMap)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_CREATE_MATERIAL };
            var m = new KernelEngine.Framework.Legacy.Native.ke_material
            {
                r = color.X, g = color.Y, b = color.Z, a = color.W,
                metallic = metallic, roughness = roughness,
            };
            m.albedo.idx     = albedo.Value;
            m.normal_map.idx = normalMap.Value;
            cmd.u.create_material.material = m;
            return _q.SubmitCreate(cmd).ContinueWith(t => new MaterialHandle(t.Result),
                TaskContinuationOptions.ExecuteSynchronously);
        }

        public MaterialHandle CreateMaterial(Vector4 color, TextureHandle albedo = default,
                                              float metallic = 0f, float roughness = 0.5f,
                                              TextureHandle normalMap = default) =>
            CreateMaterialAsync(color, albedo, metallic, roughness, normalMap).GetAwaiter().GetResult();

        public void DestroyMaterial(MaterialHandle handle)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_DESTROY_MATERIAL };
            cmd.u.destroy.handle = handle.Value;
            _q.SubmitDestroy(cmd);
        }

        public ShadowMapHandle CreateShadowMap(uint width, uint height)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_CREATE_SHADOW_MAP };
            cmd.u.create_shadow_map.width  = width;
            cmd.u.create_shadow_map.height = height;
            return new ShadowMapHandle(_q.SubmitCreate(cmd).GetAwaiter().GetResult());
        }

        public void DestroyShadowMap(ShadowMapHandle handle)
        {
            var cmd = new ke_resource_command { kind = ke_resource_command_kind.KE_RESOURCE_CMD_DESTROY_SHADOW_MAP };
            cmd.u.destroy.handle = handle.Value;
            _q.SubmitDestroy(cmd);
        }
    }
}
