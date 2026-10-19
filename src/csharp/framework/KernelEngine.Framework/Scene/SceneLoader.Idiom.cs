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
    /// Creates a native scene loader bound to <paramref name="world"/>, resolving every
    /// <c>res://</c> scene reference through <paramref name="assets"/>.
    /// </summary>
    /// <exception cref="ArgumentNullException">An argument is null.</exception>
    /// <exception cref="Exception">The native factory fails.</exception>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="assets">Resolves <c>res://</c> paths; must outlive the loader.</param>
    public SceneLoader(World world, NativeAssetResolver assets) : this(Create(world, assets))
    {
    }

    private static ke_scene_loader_handle Create(World world, NativeAssetResolver assets)
    {
        ArgumentNullException.ThrowIfNull(world);
        ArgumentNullException.ThrowIfNull(assets);

        ke_error* err = null;
        var handle = KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
            ((INativeWorld)world).Native, ((INativeAssetResolver)assets).Native, &err);
        if (handle.@ref == null) throw NativeErrors.FromNative(err, "scene_loader_create");
        return handle;
    }

    partial void OnDispose()
    {
    }
}
