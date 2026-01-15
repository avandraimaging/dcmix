defmodule Mix.Tasks.Dcmix.ToJson do
  @shortdoc "Convert DICOM file to JSON"

  @moduledoc """
  Converts a DICOM file to JSON format (DICOM JSON Model per PS3.18 F.2).

  ## Usage

      mix dcmix.to_json <input_file> [output_file]

  If no output file is specified, outputs to stdout.

  ## Options

      --pretty, -p    Pretty-print JSON output

  ## Examples

      mix dcmix.to_json patient.dcm
      mix dcmix.to_json patient.dcm patient.json
      mix dcmix.to_json --pretty patient.dcm
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [pretty: :boolean],
        aliases: [p: :pretty]
      )

    case files do
      [] ->
        Mix.shell().error("Usage: mix dcmix.to_json <input_file> [output_file]")
        exit({:shutdown, 1})

      [input_file] ->
        convert_file(input_file, nil, opts)

      [input_file, output_file | _] ->
        convert_file(input_file, output_file, opts)
    end
  end

  defp convert_file(input_file, output_file, opts) do
    unless File.exists?(input_file) do
      Mix.shell().error("File not found: #{input_file}")
      exit({:shutdown, 1})
    end

    json_opts = [pretty: Keyword.get(opts, :pretty, false)]

    with {:ok, dataset} <- Dcmix.read_file(input_file),
         {:ok, json} <- Dcmix.to_json(dataset, json_opts) do
      write_output(json, output_file)
    else
      {:error, reason} ->
        Mix.shell().error("Conversion failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp write_output(content, nil) do
    Mix.shell().info(content)
  end

  defp write_output(content, output_file) do
    File.write!(output_file, content)
    Mix.shell().info("Written to #{output_file}")
  end
end
