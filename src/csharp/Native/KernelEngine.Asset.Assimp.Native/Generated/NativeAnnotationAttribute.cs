using System;
using System.Diagnostics;

namespace KernelEngine.Asset.Assimp.Native;

[AttributeUsage(AttributeTargets.Struct | AttributeTargets.Enum | AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter | AttributeTargets.ReturnValue, AllowMultiple = true, Inherited = false)]
[Conditional("DEBUG")]
internal sealed partial class NativeAnnotationAttribute : Attribute
{
    private readonly string _annotation;
    public NativeAnnotationAttribute(string annotation) { _annotation = annotation; }
    public string Annotation => _annotation;
}
