using System.Text;
using KernelEngine.Common.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native scene loader: reads a scene file and builds its nodes,
/// components and signal connections in a <see cref="World"/>. This part declares the
/// constructor that calls the native factory; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class SceneLoader
{
    /// <summary>
    /// Creates a native scene loader bound to <paramref name="world"/>.
    /// </summary>
    /// <exception cref="ArgumentNullException"><paramref name="world"/> is null.</exception>
    /// <exception cref="InvalidOperationException">The native factory fails.</exception>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="projectRoot">
    /// Project root that <c>res://</c>-prefixed paths resolve against; with
    /// <see langword="null"/> such a path resolves to the bare remainder.
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
            if (handle.@ref == null) throw NativeErrors.FromNative(err, "scene_loader_create");
            return handle;
        }
    }

    partial void OnDispose()
    {
    }
}
