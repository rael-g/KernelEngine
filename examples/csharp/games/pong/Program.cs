using KernelEngine;
using KernelEngine.Framework.Nodes;

using Microsoft.Extensions.DependencyInjection;

using Pong;

using var services = new ServiceCollection().AddDefaultKernelEngine(AppContext.BaseDirectory).BuildServiceProvider();
var host = services.GetRequiredService<KernelEngineHost>();
host.Start();

var nodes = services.GetRequiredService<NodeWorld>();
nodes.RegisterEvent<GoalScored>();
nodes.RegisterEvent<ServeRequested>();
nodes.RegisterEvent<ScoreChanged>();
nodes.Register(new Match());
nodes.Register(new Paddle());
nodes.Register(new Ball());
nodes.Register(new Scoreboard());
nodes.Register(new MenuController());

host.Run();
