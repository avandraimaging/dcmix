defmodule Dcmix.MixProject do
  use Mix.Project

  def project do
    [
      app: :dcmix,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Dcmix",
      source_url: "https://github.com/avandra/dcmix",
      test_coverage: [
        summary: [threshold: 90]
      ]
    ]
  end

  defp description do
    "A DICOM library for Elixir - read, write, and manipulate DICOM files."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/avandra/dcmix"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end
end
