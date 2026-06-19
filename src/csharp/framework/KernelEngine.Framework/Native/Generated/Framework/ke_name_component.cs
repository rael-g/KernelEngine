using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Framework.Native;

public partial struct ke_name_component
{
    [NativeTypeName("char[64]")]
    public _name_e__FixedBuffer name;

    [InlineArray(64)]
    public partial struct _name_e__FixedBuffer
    {
        public sbyte e0;
    }
}
