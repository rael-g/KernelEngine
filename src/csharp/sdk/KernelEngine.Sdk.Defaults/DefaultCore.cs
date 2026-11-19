using KernelEngine.Async.Enki;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Io.Std;
using KernelEngine.Job.Enki;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Schedule;
using KernelEngine.Scheduler;
using KernelEngine.Settings;
using KernelEngine.Text.StbTrueType;
using KernelEngine.View;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;

namespace KernelEngine;

/// <summary>Registration of the common implementation of every part of an engine.</summary>
public static class DefaultCore
{
    /// <summary>
    /// Registers, under its contract, the common implementation of every part the host has not registered yet, each
    /// configured once by the project file in <paramref name="projectDir"/>; and the default modules, the passes among them.
    /// </summary>
    /// <param name="services">The collection the parts are registered in.</param>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    public static IServiceCollection AddDefaultCore(this IServiceCollection services, string projectDir)
    {
        var root = projectDir.TrimEnd(Path.DirectorySeparatorChar);
        static T Get<T>(IServiceProvider sp) where T : notnull => sp.GetRequiredService<T>();

        services.TryAddKeyedSingleton<Configuration.Configuration>("bootstrap", (sp, _) => new DefaultConfiguration());
        IPartSettings Bootstrap(IServiceProvider sp, string section) => sp.GetRequiredKeyedService<Configuration.Configuration>("bootstrap").Section(section);
        services.TryAddSingleton<Job.JobSystem>(sp => new EnkiJobSystem(Bootstrap(sp, "job")));
        services.TryAddSingleton<FileSystem.FileSystem>(sp => new StdFileSystem("."));
        services.TryAddSingleton<Async.Async>(sp => new EnkiAsync(Bootstrap(sp, "async")));
        services.TryAddSingleton<Io.Io>(sp => new StdIo(Get<FileSystem.FileSystem>(sp), Bootstrap(sp, "io")));
        services.TryAddSingleton<ConfigurationSource>(sp => new ConfigurationTomlConfigurationSource(Get<Io.Io>(sp)));
        services.TryAddSingleton<Configuration.Configuration>(sp =>
        {
            var config = new DefaultConfiguration();
            Get<ConfigurationSource>(sp).Load(config, Path.Combine(root, "Project"));
            return config;
        });
        services.TryAddSingleton<Input.Input>(_ => new Input.DefaultInput());
        services.TryAddSingleton<Window.Window>(sp => new GlfwWindow(Get<Input.Input>(sp), Get<Configuration.Configuration>(sp).Section("runtime.window")));
        services.TryAddSingleton<Ecs.EcsRegistry>(sp => new FlecsEcsRegistry(Get<Configuration.Configuration>(sp).Section("ecs")));
        services.TryAddKeyedSingleton<Ecs.EcsRegistry>("render", (sp, _) => new FlecsEcsRegistry(Get<Configuration.Configuration>(sp).Section("ecs")));
        services.TryAddKeyedSingleton<Schedule.Schedule>("render", (sp, _) => new DefaultSchedule(sp.GetRequiredKeyedService<Ecs.EcsRegistry>("render"), Get<Job.JobSystem>(sp), Get<Configuration.Configuration>(sp).Section("schedule")));
        services.TryAddSingleton<Extraction.Extraction>(sp => new Extraction.DefaultExtraction(Get<Ecs.EcsRegistry>(sp), sp.GetRequiredKeyedService<Ecs.EcsRegistry>("render"), Get<Scheduler.Scheduler>(sp), sp.GetRequiredKeyedService<Schedule.Schedule>("render")));
        services.TryAddSingleton<Func<Schedule.Schedule>>(sp => () => new DefaultSchedule(Get<Ecs.EcsRegistry>(sp), Get<Job.JobSystem>(sp), Get<Configuration.Configuration>(sp).Section("schedule")));
        services.TryAddSingleton<Scheduler.Scheduler>(sp => new DefaultScheduler(Get<Job.JobSystem>(sp), Get<Async.Async>(sp), Get<Configuration.Configuration>(sp).Section("scheduler")));

        services.TryAddSingleton<Render.Gpu.GpuDevice>(sp => new WebgpuGpuDevice(null, Get<Configuration.Configuration>(sp).Section("runtime.renderer.device")));
        services.AddSingleton(sp => new EngineReadiness(Get<Render.Gpu.GpuDevice>(sp) is WebgpuGpuDevice device ? device.Ready : 0));
        services.TryAddSingleton<Render.Gpu.GpuRenderTarget>(sp => new WebgpuWindowGpuRenderTarget(Get<Render.Gpu.GpuDevice>(sp), Get<Window.Window>(sp), Get<Configuration.Configuration>(sp).Section("runtime.renderer")));
        services.TryAddSingleton<Text.FontLoader>(sp => new StbFontLoader(Get<Io.Io>(sp)));
        services.TryAddSingleton<AssetResolver>(sp => new DefaultAssetResolver(null, Get<Text.FontLoader>(sp), root, Get<Io.Io>(sp)));
        services.TryAddSingleton<SceneTree>(sp => new DefaultSceneTree(Get<Ecs.EcsRegistry>(sp)));
        services.TryAddSingleton<InputActions>(sp => new DefaultInputActions(Get<Configuration.Configuration>(sp), "input"));
        services.TryAddSingleton<NodeTypes>(sp => new DefaultNodeTypes(Get<Scheduler.Scheduler>(sp), Get<Ecs.EcsRegistry>(sp), Get<SceneTree>(sp), Get<InputActions>(sp)));
        services.TryAddSingleton<SceneFiles>(sp => new DefaultSceneFiles(Get<Ecs.EcsRegistry>(sp), Get<NodeTypes>(sp), Get<AssetResolver>(sp), Get<Io.Io>(sp)));
        services.TryAddSingleton<Physics.Physics2D>(sp => new Box2DPhysics2D(Get<Job.JobSystem>(sp), Get<Configuration.Configuration>(sp).Section("runtime.physics_2d")));
        services.TryAddSingleton<Audio.Audio>(sp => new MiniaudioAudio(Get<Io.Io>(sp)));

        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, SceneHierarchyModule>(sp =>
        {
            Get<SceneTree>(sp);
            return new SceneHierarchyModule(Get<Ecs.EcsRegistry>(sp));
        }));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Physics.PhysicsBody2DModule>(sp => new Physics.PhysicsBody2DModule(Get<Ecs.EcsRegistry>(sp), Get<Physics.Physics2D>(sp), Get<SceneTree>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Audio.SoundModule>(sp => new Audio.SoundModule(Get<Ecs.EcsRegistry>(sp), Get<Audio.Audio>(sp), root)));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, InputActionsEvaluationModule>(sp => new InputActionsEvaluationModule(Get<InputActions>(sp), Get<Input.Input>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Extraction.ExtractionHistoryModule>(sp => new Extraction.ExtractionHistoryModule(Get<Extraction.Extraction>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, NodeTypesSystemsModule>(sp => new NodeTypesSystemsModule(Get<NodeTypes>(sp))));

        var shaderDir = Path.Combine(AppContext.BaseDirectory, "shaders");
        var defaultFont = Path.Combine(AppContext.BaseDirectory, "assets", "fonts", "LiberationSans-Regular.ttf");
        Ecs.EcsRegistry RenderWorld(IServiceProvider sp) => sp.GetRequiredKeyedService<Ecs.EcsRegistry>("render");
        services.TryAddSingleton<Render.Gpu.RenderResourceBinder>(sp => new GroupedRenderResourceBinder(Get<Render.Gpu.GpuDevice>(sp), Get<Io.Io>(sp), shaderDir));
        services.TryAddSingleton<RenderService>(sp => new DefaultRenderService(Get<Render.Gpu.GpuDevice>(sp), Get<Render.Gpu.GpuRenderTarget>(sp), Get<Io.Io>(sp), Get<Render.Gpu.RenderResourceBinder>(sp), shaderDir));
        services.TryAddSingleton<RenderGraph.RenderGraph>(sp => new RenderGraph.Simple.SimpleRenderGraph(Get<Render.Gpu.GpuDevice>(sp)));
        services.TryAddSingleton<ViewSpace>(sp => new RhViewSpace());
        services.TryAddSingleton<RenderCamera>(sp => new DefaultRenderCamera(Get<ViewSpace>(sp), Get<Render.Gpu.GpuDevice>(sp)));
        services.TryAddSingleton<RenderSceneResolve>(sp => new DefaultRenderSceneResolve(Get<Ecs.EcsRegistry>(sp), RenderWorld(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp)));
        services.TryAddSingleton<Render.Frame.RenderFrame>(sp => new DefaultRenderFrame(RenderWorld(sp), Get<RenderGraph.RenderGraph>(sp), Get<RenderService>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp),
            GpuTextureFormat.Rgba16Float, GpuTextureFormat.D32Float, Get<Configuration.Configuration>(sp).Section("render")));
        services.TryAddSingleton<RenderUi>(sp => new DefaultRenderUi(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp)));

        void Pass<T>(Func<IServiceProvider, T> make) where T : Module.Module => services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, T>(make));
        Pass(sp => new RenderSceneResolveSystemsModule(Get<RenderSceneResolve>(sp)));
        Pass(sp => new RenderFrameSystemsModule(Get<Render.Frame.RenderFrame>(sp)));
        Pass(sp => new RenderShadowModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp), Get<Configuration.Configuration>(sp).Section("render.shadow")));
        Pass(sp => new RenderClusterModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp), Get<Configuration.Configuration>(sp).Section("render.cluster")));
        Pass(sp => new RenderGbufferModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp)));
        Pass(sp => new RenderDeferredLightingModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp), Get<Configuration.Configuration>(sp).Section("render.deferred_lighting")));
        Pass(sp => new RenderForwardModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp), Get<Configuration.Configuration>(sp).Section("render.forward")));
        Pass(sp => new RenderTonemapModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp)));
        Pass(sp => new RenderUiSystemsModule(Get<RenderUi>(sp)));
        Pass(sp => new RenderLabelResolveModule(RenderWorld(sp), Get<Ecs.EcsRegistry>(sp), Get<Extraction.Extraction>(sp), Get<RenderService>(sp), Get<Render.Gpu.GpuDevice>(sp), Get<ViewSpace>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp), Get<Render.Frame.RenderFrame>(sp), Get<RenderUi>(sp), Get<AssetResolver>(sp), defaultFont));
        return services;
    }
}
