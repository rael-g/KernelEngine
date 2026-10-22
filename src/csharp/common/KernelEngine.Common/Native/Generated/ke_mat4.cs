using System.Runtime.CompilerServices;

using KernelEngine.Result.Native;

namespace KernelEngine.Common.Native;

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
