using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Concrete <see cref="IFrameworkBackendFactory"/> producing the C-plugin-backed implementations
/// (<see cref="NativeInputActions"/>, <see cref="NativeSceneTree"/>, <see cref="NativeSceneLoader"/>,
/// <see cref="NativeResourceCache"/>, <see cref="NativeAssetResolver"/>, <see cref="NativeResourceQueue"/>).
/// Registered via the <c>AddNativeFramework()</c> DI extension.
/// </summary>
public sealed unsafe class NativeFrameworkBackendFactory : IFrameworkBackendFactory
{
    public IInputActionsBackend CreateInputActions() =>
        new NativeInputActions(new MallocAllocator());

    public ISceneTreeBackend CreateSceneTree(IWorld world) =>
        throw new NotSupportedException("Legacy scene tree requires porting to runtime-v2 World.");

    public ISceneLoaderBackend CreateSceneLoader(IWorld world,
                                                   ISceneTreeBackend tree,
                                                   string projectRoot) =>
        throw new NotSupportedException("Legacy scene loader requires porting to runtime-v2 World.");

    public IResourceCacheBackend CreateResourceCache() =>
        new NativeResourceCache(new MallocAllocator());

    public IAssetResolverBackend CreateAssetResolver(IImageLoader? imageLoader, string projectRoot)
    {
        KernelEngine.Kernel.Native.ke_image_loader* nativeImg = null;
        if (imageLoader is INativeImageLoader ni) nativeImg = ni.Native;
        return new NativeAssetResolver(new MallocAllocator(), nativeImg, projectRoot);
    }

    public IResourceCommandQueue CreateResourceQueue() =>
        throw new NotSupportedException("NativeResourceQueue was removed in C-phase 4.5.");
}
