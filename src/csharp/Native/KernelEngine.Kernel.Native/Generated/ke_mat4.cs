using System.Runtime.CompilerServices;

namespace KernelEngine.Kernel.Native;

public partial struct ke_mat4
{
    [NativeTypeName("float[16]")]
    public _m_e__FixedBuffer m;

    [InlineArray(16)]
    public partial struct _m_e__FixedBuffer
    {
        public float e0;
    }
}
