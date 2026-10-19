using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Audio.Native;

public static partial class NativeMethods
{
    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_scene_component_set_handle")]
    public static extern KernelEngine.Framework.Native.ke_scene_component_set_handle audio_scene_components_create();
}
