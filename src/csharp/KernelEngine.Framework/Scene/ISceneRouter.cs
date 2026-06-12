namespace KernelEngine.Framework;

/// <summary>
/// Routes between scenes. Scripts request a scene swap via
/// <see cref="LoadScene"/>; the actual tear-down + load happens at the
/// start of the next tick on the render worker, so the current frame
/// finishes cleanly before the tree mutates.
/// </summary>
public interface ISceneRouter
{
    /// <summary>Name of the scene that's currently loaded, or null before the first load.</summary>
    string? CurrentScene { get; }

    /// <summary>
    /// Queues a scene swap: <c>scenes/{name}.scene</c> relative to the executable.
    /// Idempotent within a single frame — last call wins. The previous scene's
    /// nodes are destroyed (each <see cref="Node.OnUnbind"/> runs first); the
    /// renderer + audio + physics singletons survive.
    /// </summary>
    void LoadScene(string name);
}
