using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Common.Native;
using KernelEngine.Logger;

namespace KernelEngine.Input;

public sealed unsafe class InputSnapshotReader : IInputReader
{
    private readonly ke_input_snapshot _data;

    public InputSnapshotReader(ke_input_snapshot data)
    {
        _data = data;
    }

    /// <summary>
    /// Native snapshot struct backing this reader. Exposed for action-layer evaluation
    /// which needs to call <c>ke_input_actions.evaluate</c> with a raw pointer.
    /// </summary>
    public ke_input_snapshot Native => _data;

    public bool IsKeyDown(int keyCode)
    {
        if (keyCode < 0 || keyCode >= 512) return false;
        int wordIdx = keyCode / 64;
        int bitIdx  = keyCode % 64;
        return (_data.keys_down[wordIdx] & (1UL << bitIdx)) != 0;
    }

    public Vector2 MousePosition => new(_data.mouse_x, _data.mouse_y);
    public Vector2 MouseDelta    => new(_data.mouse_dx, _data.mouse_dy);
    public Vector2 ScrollDelta   => new(_data.scroll_dx, _data.scroll_dy);

    public bool IsMouseButtonDown(int button) => (_data.mouse_buttons_down & (1u << button)) != 0;
}
