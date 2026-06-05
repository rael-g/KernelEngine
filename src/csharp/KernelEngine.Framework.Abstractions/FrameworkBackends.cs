namespace KernelEngine.Framework;

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
}
