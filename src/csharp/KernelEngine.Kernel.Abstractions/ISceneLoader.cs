namespace KernelEngine.Kernel;

/// <summary>
/// Language-agnostic scene loader contract (Tier S — S3).
/// <para>
/// Mirrors <c>ke_scene_loader</c> in the C kernel ABI. The C# Framework provides
/// <c>CSharpSceneLoader</c> as the round-trip implementation; a future C++ TOML
/// plugin will replace it without touching any managed code.
/// </para>
/// </summary>
public interface ISceneLoader
{
    /// <summary>Loads the scene file at <paramref name="path"/> into the associated tree.</summary>
    Task LoadAsync(string path);
}
