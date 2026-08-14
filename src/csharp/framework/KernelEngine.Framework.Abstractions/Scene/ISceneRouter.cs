namespace KernelEngine.Framework;

/// <summary>
/// Allows game code to query and navigate between named scenes without depending
/// on the concrete <c>SceneRouter</c> or Toolkit types.
/// </summary>
public interface ISceneRouter
{
    /// <summary>The scene currently loaded, or <see langword="null"/> before the first load.</summary>
    string? CurrentScene { get; }

    /// <summary>
    /// Schedules a transition to the scene registered as <paramref name="name"/>.
    /// The transition is deferred to the next frame boundary to avoid mutating
    /// the scene graph while it is being iterated.
    /// </summary>
    void LoadScene(string name);

    /// <summary>
    /// Schedules a transition to <typeparamref name="TScene"/>, the type generated
    /// for a scene file in this project.
    /// </summary>
    /// <remarks>
    /// A scene is a prefab: it has an identity, and an identity deserves a type.
    /// Naming one with a string means a typo is a runtime surprise, and renaming a
    /// scene file leaves every caller compiling.
    /// </remarks>
    void LoadScene<TScene>() where TScene : IScene => LoadScene(TScene.SceneName);
}

/// <summary>
/// Implemented by the type generated for each <c>.scene</c> file in a project, so
/// a scene can be named to <see cref="ISceneRouter.LoadScene{TScene}"/> by type.
/// </summary>
public interface IScene
{
    /// <summary>The scene's file name, without extension — what the loader resolves.</summary>
    static abstract string SceneName { get; }
}
