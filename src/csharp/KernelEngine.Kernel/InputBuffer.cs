using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

internal sealed unsafe class InputSnapshotReader : IInputReader
{
    private readonly ke_input_snapshot _data;

    public InputSnapshotReader(ke_input_snapshot data)
    {
        _data = data;
    }

    public bool IsKeyDown(int keyCode)
    {
        if (keyCode < 0 || keyCode >= 512) return false;
        int wordIdx = keyCode / 64;
        int bitIdx  = keyCode % 64;
        return (_data.keys_down[wordIdx] & (1UL << bitIdx)) != 0;
    }

    public bool IsKeyPressed(int keyCode)
    {
        if (keyCode < 0 || keyCode >= 512) return false;
        int wordIdx = keyCode / 64;
        int bitIdx  = keyCode % 64;
        return (_data.keys_pressed[wordIdx] & (1UL << bitIdx)) != 0;
    }

    public bool IsKeyReleased(int keyCode)
    {
        if (keyCode < 0 || keyCode >= 512) return false;
        int wordIdx = keyCode / 64;
        int bitIdx  = keyCode % 64;
        return (_data.keys_released[wordIdx] & (1UL << bitIdx)) != 0;
    }

    public Vector2 MousePosition => new(_data.mouse_x, _data.mouse_y);
    public Vector2 MouseDelta    => new(_data.mouse_dx, _data.mouse_dy);
    public Vector2 ScrollDelta   => new(_data.scroll_dx, _data.scroll_dy);

    public bool IsMouseButtonDown(int button) => (_data.mouse_buttons_down & (1u << button)) != 0;
    public bool IsMouseButtonPressed(int button) => (_data.mouse_buttons_pressed & (1u << button)) != 0;
    public bool IsMouseButtonReleased(int button) => (_data.mouse_buttons_released & (1u << button)) != 0;
}

/// <summary>
/// Lock-free single-slot exchange of <see cref="IInputReader"/> between ke.main (producer)
/// and ke.sim (consumer).
/// </summary>
public sealed class InputBuffer : IInputBuffer
{
    private static readonly IInputReader Empty = new InputSnapshotReader(default);
    private IInputReader _latest = Empty;

    public void Produce(IInputReader snapshot) => Volatile.Write(ref _latest, snapshot);
    public IInputReader Consume() => Volatile.Read(ref _latest);
}
