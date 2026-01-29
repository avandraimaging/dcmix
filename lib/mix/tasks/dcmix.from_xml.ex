defmodule Mix.Tasks.Dcmix.FromXml do
  @shortdoc "Convert XML file to DICOM"

  @moduledoc """
  Converts a DICOM XML file (Native DICOM Model) to DICOM format.

  Similar to dcmtk's `xml2dcm`.

  ## Usage

      mix dcmix.from_xml <input_xml> <output_dcm>

  ## Options

      -t, --template <file>    Use DICOM file as template (merge XML into it)

  ## Examples

      mix dcmix.from_xml patient.xml patient.dcm
      mix dcmix.from_xml --template template.dcm patient.xml patient.dcm
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [template: :string],
        aliases: [t: :template]
      )

    case files do
      [input_file, output_file] ->
        convert_file(input_file, output_file, opts)

      _ ->
        Mix.shell().error(
          "Usage: mix dcmix.from_xml [--template <file>] <input_xml> <output_dcm>"
        )

        exit({:shutdown, 1})
    end
  end

  defp convert_file(input_file, output_file, opts) do
    unless File.exists?(input_file) do
      Mix.shell().error("File not found: #{input_file}")
      exit({:shutdown, 1})
    end

    decode_opts = build_decode_opts(opts)

    with {:ok, dataset} <- Dcmix.from_xml_file(input_file, decode_opts),
         :ok <- Dcmix.write_file(dataset, output_file) do
      Mix.shell().info("Written to #{output_file}")
    else
      {:error, reason} ->
        Mix.shell().error("Conversion failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp build_decode_opts(opts) do
    case Keyword.get(opts, :template) do
      nil ->
        []

      template_path ->
        case Dcmix.read_file(template_path) do
          {:ok, template} ->
            [template: template]

          {:error, reason} ->
            Mix.shell().error("Failed to read template: #{inspect(reason)}")
            exit({:shutdown, 1})
        end
    end
  end
end
