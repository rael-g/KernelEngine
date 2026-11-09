using KernelEngine;

using Pong;

using var engine = Engine.Create(AppContext.BaseDirectory);

engine.Nodes.RegisterEvent<GoalScored>();
engine.Nodes.RegisterEvent<BallLaunched>();
var game = new Game();
engine.Nodes.Register(new Paddle());
engine.Nodes.Register(new Ball(game));
engine.Nodes.Register(new Scoreboard());
engine.Nodes.Register(new MenuController(game));

engine.Run();
