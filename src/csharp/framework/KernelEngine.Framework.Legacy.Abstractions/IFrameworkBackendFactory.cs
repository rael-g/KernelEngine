using KernelEngine.Asset;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Constructs the runtime backends the sugar layer depends on. Registered as a singleton by
/// the chosen backend assembly (today only <c>KernelEngine.Framework.Legacy.Native</c> via
/// <c>AddNativeFramework()</c>), and resolved once the renderer and loaders are ready, since
/// some backends (such as the asset resolver) need other plugins injected.
/// </summary>
public interface IFrameworkBackendFactory
{
    IInputActionsBackend  CreateInputActions();
    ISceneTreeBackend     CreateSceneTree(IWorld world);
    ISceneLoaderBackend   CreateSceneLoader(IWorld world,
                                             ISceneTreeBackend tree,
                                             string projectRoot);
    IResourceCacheBackend CreateResourceCache();
    IAssetResolverBackend CreateAssetResolver(IImageLoader? imageLoader, string projectRoot);
}
