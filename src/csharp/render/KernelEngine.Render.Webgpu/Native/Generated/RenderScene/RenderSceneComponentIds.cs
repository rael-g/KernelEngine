using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct RenderSceneComponentIds
{
    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Mesh;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Camera;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId DirectionalLight;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId PointLight;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId SpotLight;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId AmbientLight;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Skybox;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Sprite2d;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Label;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId WorldTransform;
}
