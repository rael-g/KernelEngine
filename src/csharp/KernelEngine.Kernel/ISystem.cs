namespace KernelEngine.Kernel;

/// <summary>
/// A managed simulation system registered with <see cref="World.AddSystem"/>.
/// Called once per frame after the built-in C systems (Script + Transform).
/// </summary>
public interface ISystem
{
    /// <summary>Advances this system by one frame.</summary>
    void Update(World world, float dt);
}
