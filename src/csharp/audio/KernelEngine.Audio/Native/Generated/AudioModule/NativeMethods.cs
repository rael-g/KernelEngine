using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Audio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_register_scene_apply", ExactSpelling = true)]
    [return: NativeTypeName("bool")]
    public static extern byte audio_register_scene_apply([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_world *")] KernelEngine.Framework.Native.ke_world* world);
}
