using KernelEngine.Common.Native;
using System.Diagnostics.CodeAnalysis;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_variant
{
    public ke_variant_type type;

    [NativeTypeName("__AnonymousRecord_variant_L32_C9")]
    public _Anonymous_e__Union Anonymous;

    [UnscopedRef]
    public ref bool b
    {
        get
        {
            return ref Anonymous.b;
        }
    }

    [UnscopedRef]
    public ref long i
    {
        get
        {
            return ref Anonymous.i;
        }
    }

    [UnscopedRef]
    public ref double f
    {
        get
        {
            return ref Anonymous.f;
        }
    }

    [UnscopedRef]
    public ref sbyte* s
    {
        get
        {
            return ref Anonymous.s;
        }
    }

    [UnscopedRef]
    public ref ke_vec2 v2
    {
        get
        {
            return ref Anonymous.v2;
        }
    }

    [UnscopedRef]
    public ref ke_vec3 v3
    {
        get
        {
            return ref Anonymous.v3;
        }
    }

    [UnscopedRef]
    public ref ke_vec4 v4
    {
        get
        {
            return ref Anonymous.v4;
        }
    }

    [UnscopedRef]
    public ref ke_quat q
    {
        get
        {
            return ref Anonymous.q;
        }
    }

    [UnscopedRef]
    public ref ke_variant_table* t
    {
        get
        {
            return ref Anonymous.t;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    public unsafe partial struct _Anonymous_e__Union
    {
        [FieldOffset(0)]
        public bool b;

        [FieldOffset(0)]
        [NativeTypeName("int64_t")]
        public long i;

        [FieldOffset(0)]
        public double f;

        [FieldOffset(0)]
        [NativeTypeName("const char *")]
        public sbyte* s;

        [FieldOffset(0)]
        public ke_vec2 v2;

        [FieldOffset(0)]
        public ke_vec3 v3;

        [FieldOffset(0)]
        public ke_vec4 v4;

        [FieldOffset(0)]
        public ke_quat q;

        [FieldOffset(0)]
        [NativeTypeName("const struct ke_variant_table *")]
        public ke_variant_table* t;
    }
}
