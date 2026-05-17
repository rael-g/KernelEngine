using System.Collections.Concurrent;
using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

public enum ResourceCommandType
{
    CreateMesh,
    DestroyMesh,
    CreateTexture,
    CreateCubemap,
    DestroyTexture,
    CreateMaterial,
    DestroyMaterial,
    CreateShadowMap,
    DestroyShadowMap
}

public struct ResourceCommand
{
    public ResourceCommandType Type;
    public object?             Data;
    public TaskCompletionSource<uint>? CompletionSource;
}

public sealed class ResourceCommandQueue
{
    private readonly ConcurrentQueue<ResourceCommand> _queue = new();

    public void Enqueue(ResourceCommand command)
    {
        _queue.Enqueue(command);
    }

    public void Drain(IRenderer renderer)
    {
        KernelThread.AssertCurrent("ke.render");

        while (_queue.TryDequeue(out var cmd))
        {
            try
            {
                switch (cmd.Type)
                {
                    case ResourceCommandType.CreateMesh:
                        var (verts, indices) = ((ke_vertex[], ushort[]))cmd.Data!;
                        var meshRes = renderer.CreateMesh(verts, indices);
                        cmd.CompletionSource?.SetResult(meshRes.Value.Value);
                        break;

                    case ResourceCommandType.DestroyMesh:
                        renderer.DestroyMesh(new MeshHandle((uint)cmd.Data!));
                        cmd.CompletionSource?.SetResult(0);
                        break;

                    case ResourceCommandType.CreateTexture:
                        var (w, h, px) = ((uint, uint, byte[]))cmd.Data!;
                        var texRes = renderer.CreateTexture(w, h, px);
                        cmd.CompletionSource?.SetResult(texRes.Value.Value);
                        break;

                    case ResourceCommandType.CreateCubemap:
                        var (size, data) = ((uint, byte[]))cmd.Data!;
                        var cubeRes = renderer.CreateCubemap(size, data);
                        cmd.CompletionSource?.SetResult(cubeRes.Value.Value);
                        break;

                    case ResourceCommandType.DestroyTexture:
                        renderer.DestroyTexture(new TextureHandle((uint)cmd.Data!));
                        cmd.CompletionSource?.SetResult(0);
                        break;

                    case ResourceCommandType.CreateMaterial:
                        var mData = ((Vector4, TextureHandle, float, float, TextureHandle))cmd.Data!;
                        var matRes = renderer.CreateMaterial(mData.Item1, mData.Item2, mData.Item3, mData.Item4, mData.Item5);
                        cmd.CompletionSource?.SetResult(matRes.Value.Value);
                        break;

                    case ResourceCommandType.DestroyMaterial:
                        renderer.DestroyMaterial(new MaterialHandle((uint)cmd.Data!));
                        cmd.CompletionSource?.SetResult(0);
                        break;

                    case ResourceCommandType.CreateShadowMap:
                        var (sw, sh) = ((uint, uint))cmd.Data!;
                        var shadowRes = renderer.CreateShadowMap(sw, sh);
                        cmd.CompletionSource?.SetResult(shadowRes.Value.Value);
                        break;

                    case ResourceCommandType.DestroyShadowMap:
                        renderer.DestroyShadowMap(new ShadowMapHandle((uint)cmd.Data!));
                        cmd.CompletionSource?.SetResult(0);
                        break;
                }
            }
            catch (Exception ex)
            {
                cmd.CompletionSource?.SetException(ex);
            }
        }
    }
}
