using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;
using KernelEngine.Configuration;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Render.Bgfx;
using KernelEngine.Physics.Box2D;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Text.StbTrueType;
using KernelEngine.CSharp;

var services = new ServiceCollection().AddKernel().AddNativeFramework().AddLogger().AddConsoleSink().AddInput().AddProjectConfig().AddInputActions().AddGlfwWindow().AddBgfxRenderer().AddBox2D().AddMiniAudio().AddAudioFramework().AddTextStbTrueType().AddCSharpPlugin();
using var app = new Application();
app.Run(services);