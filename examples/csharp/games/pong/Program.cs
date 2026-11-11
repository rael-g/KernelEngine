using KernelEngine;

using Pong;

using var engine = Engine.Create(AppContext.BaseDirectory);

engine.Nodes.RegisterEvent<GoalScored>();
engine.Nodes.RegisterEvent<ServeRequested>();
engine.Nodes.RegisterEvent<ScoreChanged>();
engine.Nodes.Register(new Match());
engine.Nodes.Register(new Paddle());
engine.Nodes.Register(new Ball());
engine.Nodes.Register(new Scoreboard());
engine.Nodes.Register(new MenuController());

engine.Run();
