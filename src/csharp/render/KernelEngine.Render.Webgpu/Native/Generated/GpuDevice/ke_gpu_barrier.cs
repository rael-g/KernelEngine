using KernelEngine.Common.Native;
using System.Diagnostics.CodeAnalysis;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_barrier
{
    public ke_gpu_barrier_type type;

    [NativeTypeName("__AnonymousRecord_gpu_device_L267_C5")]
    public _Anonymous_e__Union Anonymous;

    [UnscopedRef]
    public ref ke_gpu_buffer_barrier buffer
    {
        get
        {
            return ref Anonymous.buffer;
        }
    }

    [UnscopedRef]
    public ref ke_gpu_texture_barrier texture
    {
        get
        {
            return ref Anonymous.texture;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    public partial struct _Anonymous_e__Union
    {
        [FieldOffset(0)]
        public ke_gpu_buffer_barrier buffer;

        [FieldOffset(0)]
        public ke_gpu_texture_barrier texture;
    }
}
