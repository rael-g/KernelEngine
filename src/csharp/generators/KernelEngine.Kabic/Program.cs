string[] withCache = args is ["--cache-dir", ..] ? args : ["--cache-dir", Path.Combine("build", "kabic-cache"), .. args];
return Kabic.Cli.KabicCli.Run(withCache, [new KernelEngine.Kabic.ResultCodesExtension(), new Kabic.Factories.FactoriesExtension(), new KernelEngine.Kabic.KernelEngineExtension(), new KernelEngine.Kabic.FieldTablesExtension(), new KernelEngine.Kabic.NodeBasesExtension()]);
