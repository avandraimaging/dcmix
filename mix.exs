defmodule Dcmix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/avandra/dcmix"

  def project do
    [
      app: :dcmix,
      version: @version,
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Dcmix",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
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
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/USAGE.md": [title: "Usage Guide"],
        "docs/TRANSFER_SYNTAXES.md": [title: "Transfer Syntaxes"],
        "docs/ROADMAP.md": [title: "Roadmap"],
        "CHANGELOG.md": [title: "Changelog"],
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [Dcmix, Dcmix.DataSet, Dcmix.DataElement, Dcmix.Tag, Dcmix.VR],
        Parsing: [Dcmix.Parser, Dcmix.Parser.ExplicitVR, Dcmix.Parser.ImplicitVR],
        Writing: [Dcmix.Writer, Dcmix.Writer.ExplicitVR, Dcmix.Writer.ImplicitVR],
        Export: [Dcmix.Export.JSON, Dcmix.Export.XML, Dcmix.Export.Text, Dcmix.Export.Image],
        Import: [Dcmix.Import.JSON, Dcmix.Import.XML, Dcmix.Import.Image],
        Support: [Dcmix.Dictionary, Dcmix.PixelData, Dcmix.PrivateTag]
      ]
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
      {:png, "~> 0.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end
end
