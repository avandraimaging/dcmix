defmodule Mix.Tasks.Dcmix.Dump do
  @shortdoc "Dump DICOM file contents to stdout"

  @moduledoc """
  Dumps the contents of a DICOM file to the terminal.

  ## Usage

      mix dcmix.dump <file>

  ## Options

      --max-length, -m  Maximum length for value display (default: 64)
      --no-length       Don't show element lengths

  ## Examples

      mix dcmix.dump patient.dcm
      mix dcmix.dump --max-length 128 patient.dcm
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [max_length: :integer, no_length: :boolean],
        aliases: [m: :max_length]
      )

    case files do
      [] ->
        Mix.shell().error("Usage: mix dcmix.dump <file>")
        exit({:shutdown, 1})

      [file | _] ->
        dump_file(file, opts)
    end
  end

  defp dump_file(file, opts) do
    unless File.exists?(file) do
      Mix.shell().error("File not found: #{file}")
      exit({:shutdown, 1})
    end

    case Dcmix.read_file(file) do
      {:ok, dataset} ->
        dump_opts = [
          max_value_length: Keyword.get(opts, :max_length, 64),
          show_length: not Keyword.get(opts, :no_length, false)
        ]

        output = Dcmix.dump(dataset, dump_opts)
        Mix.shell().info(output)

      {:error, reason} ->
        Mix.shell().error("Failed to parse file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
