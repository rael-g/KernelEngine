using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Process-wide entry point that the backend assembly populates so static sugar entry points
/// (<see cref="SceneLoader"/>.Load, <see cref="InputActionMap{TEnum}"/>'s parameterless ctor,
/// etc.) can reach a backend without taking a DI dependency.
/// <para>
/// Set once by the backend's DI extension (typically <c>AddNativeFramework()</c>); read by
/// the sugar layer at the moments where injecting a factory would force every caller to
/// thread it through.
/// </para>
/// </summary>
public static class FrameworkBackends
{
    /// <summary>
    /// Active backend factory. <c>null</c> until a backend assembly registers one (the throw
    /// path on access is the failure mode that surfaces "you forgot AddNativeFramework()").
    /// </summary>
    public static IFrameworkBackendFactory? Default { get; set; }

    /// <summary>Returns <see cref="Default"/> or throws a descriptive message.</summary>
    public static IFrameworkBackendFactory Required => Default
        ?? throw new InvalidOperationException(
            "No framework backend registered. Call services.AddNativeFramework() during DI setup " +
            "(or set FrameworkBackends.Default explicitly for tests).");

    /// <summary>
    /// Resolves the <c>scene_properties</c> bag attached to an entity. Set by
    /// <c>AddNativeFramework()</c>; defaults to returning <see cref="EmptySceneProperties.Instance"/>
    /// (so <see cref="Node.Properties"/> stays usable in tests that don't bring up the backend).
    /// The sugar layer's <c>Node.Properties</c> accessor calls this; nobody else should.
    /// </summary>
    public static Func<IWorld, ulong, ISceneProperties> ScenePropertiesResolver { get; set; }
        = static (_, _) => EmptySceneProperties.Instance;

    /// <summary>
    /// Active resource manager (typed <c>ResourceManager</c>; opaque here because the type lives
    /// in <c>KernelEngine.Framework.Legacy</c> which Abstractions can't reference). Set by
    /// <c>Application</c> when GPU resource creation is ready; read by Node subclasses
    /// (MeshRenderer) that resolve scene-authored material colors during <see cref="Node.Start"/>
    /// via a typed wrapper in the Framework assembly. <c>null</c> until init.
    /// </summary>
    public static object? Resources { get; set; }
}
