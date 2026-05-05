using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

[StructLayout(LayoutKind.Sequential)]
public unsafe struct ke_input_snapshot
{
    public fixed ulong keys_down[8];
    public fixed ulong keys_pressed[8];
    public fixed ulong keys_released[8];

    public float mouse_x;
    public float mouse_y;
    public float mouse_dx;
    public float mouse_dy;
    public float scroll_dx;
    public float scroll_dy;

    public uint mouse_buttons_down;
    public uint mouse_buttons_pressed;
    public uint mouse_buttons_released;
}
