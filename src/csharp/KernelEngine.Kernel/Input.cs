using System.Numerics;

using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Tracks keyboard and mouse state. Reads messages from the <see cref="MessagePipe"/>.
/// </summary>
public sealed unsafe class Input : IDisposable
{
    private ke_input* _native;

    public Input(Allocator allocator, Logger? logger, MessagePipe messagePipe)
    {
        ke_input* native;
        var res = NativeMethods.input_create(
            allocator.Native,
            logger != null ? logger.Native : null,
            messagePipe.Native,
            &native);

        KernelException.ThrowIfFailed(res, nameof(NativeMethods.input_create));
        _native = native;
    }

    /// <summary>Updates internal state by processing pending messages in the pipe.</summary>
    public Result Update() => _native->update(_native);

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
