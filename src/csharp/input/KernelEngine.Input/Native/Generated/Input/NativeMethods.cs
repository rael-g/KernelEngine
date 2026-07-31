using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Input.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_key_down", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_key_down([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int key);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_key_pressed", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_key_pressed([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int key);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_key_released", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_key_released([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int key);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_mouse_button_down", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_mouse_button_down([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int button);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_mouse_button_pressed", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_mouse_button_pressed([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int button);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_snapshot_is_mouse_button_released", ExactSpelling = true)]
    [return: NativeTypeName("ke_bool")]
    public static extern byte input_snapshot_is_mouse_button_released([NativeTypeName("const ke_input_snapshot *")] ke_input_snapshot* snapshot, [NativeTypeName("int32_t")] int button);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    public static extern ke_input_handle input_create([NativeTypeName("struct ke_logger *")] KernelEngine.Logger.Native.ke_logger* logger, ke_error** out_error);
}
