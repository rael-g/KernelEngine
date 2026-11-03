using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderSceneComponentIds
{
    public global::KernelEngine.Ecs.ComponentId Mesh;
    public global::KernelEngine.Ecs.ComponentId Camera;
    public global::KernelEngine.Ecs.ComponentId DirectionalLight;
    public global::KernelEngine.Ecs.ComponentId PointLight;
    public global::KernelEngine.Ecs.ComponentId SpotLight;
    public global::KernelEngine.Ecs.ComponentId AmbientLight;
    public global::KernelEngine.Ecs.ComponentId Skybox;
    public global::KernelEngine.Ecs.ComponentId Sprite2d;
    public global::KernelEngine.Ecs.ComponentId Label;
    public global::KernelEngine.Ecs.ComponentId WorldTransform;
}
