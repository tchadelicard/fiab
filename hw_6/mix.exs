defmodule ImtOrder.MixProject do
  use Mix.Project

  def project do
    [
      app: :imt_order,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {ImtSandbox.App,[]}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:poison, "~> 4.0.1"},
      {:plug_cowboy, "~> 2.5.2"},
      {:libring, "~> 1.0"}
    ]
  end
end
