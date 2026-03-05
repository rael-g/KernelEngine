using System.Diagnostics;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// The simulation world — owns the scene graph and drives per-frame updates.
/// </summary>
public sealed unsafe class World : IDisposable
{
    private ke_world* _native;
    private Scene? _scene;

    internal ke_world* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private TimeSpan _lastTime;

    private World(ke_world* native) => _native = native;

    /// <summary>Creates a world bound to the given renderer and window.</summary>
    public World(Allocator allocator, Renderer renderer, Window window)
    {
        var desc = new ke_world_descriptor
        {
            allocator = allocator.Native,
            renderer = renderer.Native,
            window = window.Native,
        };
        ke_world* world;
        KernelException.ThrowIfFailed(NativeMethods.world_create(&desc, &world));
        _native = world;
    }

    /// <summary>The scene graph managed by this world.</summary>
    public Scene Scene => _scene ??= new Scene(Native->get_scene(Native));

    /// <summary>Advances the simulation by one frame.</summary>
    public void Update()
    {
        var now = _stopwatch.Elapsed;
        var dt = (float)(now - _lastTime).TotalSeconds;
        _lastTime = now;

        foreach (var node in Node.AllScripted)
            node.InvokeLifecycle(dt);

        KernelException.ThrowIfFailed(Native->update(Native, null));
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
            _scene = null;
        }
    }
}
