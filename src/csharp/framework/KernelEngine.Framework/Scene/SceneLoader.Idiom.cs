using System.Text;
using KernelEngine.Common.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The one part of <see cref="SceneLoader"/> that is not a direct image of the C ABI:
/// the constructor's factory call, because <c>ke_scene_loader_create</c> lives outside
/// this domain's own headers, alongside the world/asset-resolver factories. Everything
/// that mirrors the vtable 1:1 is generated in <c>Generated/SceneLoader.g.cs</c>.
/// </summary>
public unsafe partial class SceneLoader
{
    /// <summary>
    /// Creates a native scene loader bound to <paramref name="world"/>.
    /// </summary>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="projectRoot">
    /// Optional project root for resolving <c>res://</c>-prefixed paths. Pass
    /// <see langword="null"/> to disable res:// resolution.
    /// </param>
    public SceneLoader(World world, string? projectRoot = null) : this(Create(world, projectRoot))
    {
    }

    private static ke_scene_loader_handle Create(World world, string? projectRoot)
    {
        ArgumentNullException.ThrowIfNull(world);

        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        fixed (byte* rootPtr = rootBytes)
        {
            ke_error* err = null;
            var handle = KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
                ((INativeWorld)world).Native, (sbyte*)rootPtr, &err);
            if (handle.@ref == null) throw KernelError.FromNative(err, "scene_loader_create");
            return handle;
        }
    }

    partial void OnDispose()
    {
    }
}
