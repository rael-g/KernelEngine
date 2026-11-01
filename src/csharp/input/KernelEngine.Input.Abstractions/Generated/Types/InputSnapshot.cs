using System.Numerics;
using System.Runtime.CompilerServices;

namespace KernelEngine.Input;

public partial struct InputSnapshot
{
    public _KeysDown_e__FixedBuffer KeysDown;
    public _KeysPressed_e__FixedBuffer KeysPressed;
    public _KeysReleased_e__FixedBuffer KeysReleased;

    public float MouseX;

    public float MouseY;

    public float MouseDx;

    public float MouseDy;

    public float ScrollDx;

    public float ScrollDy;
    public uint MouseButtonsDown;
    public uint MouseButtonsPressed;
    public uint MouseButtonsReleased;
    public uint EventsDropped;

    [InlineArray(8)]
    public partial struct _KeysDown_e__FixedBuffer
    {
        public ulong e0;
    }

    [InlineArray(8)]
    public partial struct _KeysPressed_e__FixedBuffer
    {
        public ulong e0;
    }

    [InlineArray(8)]
    public partial struct _KeysReleased_e__FixedBuffer
    {
        public ulong e0;
    }
}
