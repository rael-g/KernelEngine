using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Input.Native;

public partial struct ke_input_snapshot
{
    [NativeTypeName("uint64_t[8]")]
    public _keys_down_e__FixedBuffer keys_down;

    [NativeTypeName("uint64_t[8]")]
    public _keys_pressed_e__FixedBuffer keys_pressed;

    [NativeTypeName("uint64_t[8]")]
    public _keys_released_e__FixedBuffer keys_released;

    public float mouse_x;

    public float mouse_y;

    public float mouse_dx;

    public float mouse_dy;

    public float scroll_dx;

    public float scroll_dy;

    [NativeTypeName("uint32_t")]
    public uint mouse_buttons_down;

    [NativeTypeName("uint32_t")]
    public uint mouse_buttons_pressed;

    [NativeTypeName("uint32_t")]
    public uint mouse_buttons_released;

    [InlineArray(8)]
    public partial struct _keys_down_e__FixedBuffer
    {
        public ulong e0;
    }

    [InlineArray(8)]
    public partial struct _keys_pressed_e__FixedBuffer
    {
        public ulong e0;
    }

    [InlineArray(8)]
    public partial struct _keys_released_e__FixedBuffer
    {
        public ulong e0;
    }
}
