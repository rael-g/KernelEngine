using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuShaderLanguage : uint
{
    LangWgsl = 0,
    LangSpirv = 1,
    LangMsl = 2,
    LangDxil = 3,
}
