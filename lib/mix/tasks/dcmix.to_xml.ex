defmodule Mix.Tasks.Dcmix.ToXml do
  @shortdoc "Convert DICOM file to XML"

  @moduledoc """
  Converts a DICOM file to XML format (Native DICOM Model per PS3.19).

  ## Usage

      mix dcmix.to_xml <input_file> [output_file]

  If no output file is specified, outputs to stdout.

  ## Options

      --no-pretty    Don't pretty-print XML output

  ## Examples

      mix dcmix.to_xml patient.dcm
      mix dcmix.to_xml patient.dcm patient.xml
      mix dcmix.to_xml --no-pretty patient.dcm
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [no_pretty: :boolean]
      )

    case files do
      [] ->
        Mix.shell().error("Usage: mix dcmix.to_xml <input_file> [output_file]")
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

    case Dcmix.read_file(input_file) do
      {:ok, dataset} ->
        xml_opts = [pretty: not Keyword.get(opts, :no_pretty, false)]

        case Dcmix.to_xml(dataset, xml_opts) do
          {:ok, xml} ->
            if output_file do
              File.write!(output_file, xml)
              Mix.shell().info("Written to #{output_file}")
            else
              Mix.shell().info(xml)
            end

          {:error, reason} ->
            Mix.shell().error("Failed to encode XML: #{inspect(reason)}")
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Failed to parse file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
