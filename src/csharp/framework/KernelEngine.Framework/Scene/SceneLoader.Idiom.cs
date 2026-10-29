
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
    /// <c>res://</c> scene reference through <paramref name="assets"/> and reading every scene
    /// file through <paramref name="io"/>.
    /// </summary>
    /// <exception cref="ArgumentNullException">An argument is null.</exception>
    /// <exception cref="Exception">The native factory fails.</exception>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="assets">Resolves <c>res://</c> paths; must outlive the loader.</param>
    /// <param name="io">Reads the scene files; must outlive the loader.</param>
    public SceneLoader(World world, NativeAssetResolver assets, KernelEngine.Io.INativeIo io) : this(Create(world, assets, io))
    {
    }

    private static ke_scene_loader_handle Create(World world, NativeAssetResolver assets, KernelEngine.Io.INativeIo io)
    {
        ArgumentNullException.ThrowIfNull(world);
        ArgumentNullException.ThrowIfNull(assets);
        ArgumentNullException.ThrowIfNull(io);

        ke_scene_loader_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
            ((INativeWorld)world).Native, ((INativeAssetResolver)assets).Native, io.Native, &handle), "ke_scene_loader_create");
        return handle;
    }

    partial void OnDispose()
    {
    }
}
