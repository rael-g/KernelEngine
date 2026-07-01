using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Runtime.Native;

public partial struct ke_query_decl
{
    [NativeTypeName("ke_component_access[8]")]
    public _terms_e__FixedBuffer terms;

    [NativeTypeName("uint32_t")]
    public uint term_count;

    [InlineArray(8)]
    public partial struct _terms_e__FixedBuffer
    {
        public ke_component_access e0;
    }
}
