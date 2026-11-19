string[] withCache = args is ["--cache-dir", ..] ? args : ["--cache-dir", Path.Combine("build", "kabic-cache"), .. args];
return Kabic.Cli.KabicCli.Run(withCache, [new Kabic.Factories.FactoriesExtension(), new KernelEngine.Kabic.FieldTablesExtension()]);
