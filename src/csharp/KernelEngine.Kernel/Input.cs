using System.Numerics;

using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Tracks keyboard and mouse state. Reads messages from the <see cref="MessagePipe"/>.
/// </summary>
public sealed unsafe class Input : IDisposable
{
    // ── Static Access ────────────────────────────────────────────────────────

    [ThreadStatic]
    private static IInputReader? s_currentReader;

    /// <summary>
    /// Accesses the input snapshot for the current frame.
    /// Available during <see cref="ISystem.Update"/> and <see cref="Node.OnUpdate"/>.
    /// </summary>
    public static IInputReader Current => s_currentReader ?? throw new InvalidOperationException("Input.Current is only available during the simulation update.");

    internal static void SetCurrentReader(IInputReader? reader) => s_currentReader = reader;

    // ── Instance members ──────────────────────────────────────────────────────

    private ke_input* _native;

    internal ke_input* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    public Input(Allocator allocator, Logger? logger)
    {
        ke_input* native;
        var res = NativeMethods.input_create(
            allocator.Native,
            logger != null ? logger.Native : null,
            &native);

        KernelException.ThrowIfFailed(res.ToManaged(), nameof(NativeMethods.input_create));
        _native = native;
    }

    /// <summary>Updates internal state by processing pending messages in the pipe.</summary>
    public Result Update()
    {
        KernelThread.AssertCurrent("ke.main");
        return _native->update(_native).Wrap();
    }

    /// <summary>Captures a frozen snapshot of the current input state.</summary>
    public ke_input_snapshot GetSnapshot()
    {
        KernelThread.AssertCurrent("ke.main");
        ke_input_snapshot snapshot;
        _native->get_snapshot(_native, &snapshot);
        return snapshot;
    }

    /// <summary>Returns true if the key was pressed this frame.</summary>
    public bool IsKeyPressed(int key) => _native->is_key_pressed(_native, key) != 0;

    /// <summary>Returns true if the key was released this frame.</summary>
    public bool IsKeyReleased(int key) => _native->is_key_released(_native, key) != 0;

    /// <summary>Returns true if the key is currently held down.</summary>
    public bool IsKeyDown(int key) => _native->is_key_down(_native, key) != 0;

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
