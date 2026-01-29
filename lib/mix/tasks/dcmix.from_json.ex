defmodule Mix.Tasks.Dcmix.FromJson do
  @shortdoc "Convert JSON file to DICOM"

  @moduledoc """
  Converts a DICOM JSON file to DICOM format.

  Similar to dcm4che's `json2dcm`.

  ## Usage

      mix dcmix.from_json <input_json> <output_dcm>

  ## Options

      -t, --template <file>    Use DICOM file as template (merge JSON into it)

  ## Examples

      mix dcmix.from_json patient.json patient.dcm
      mix dcmix.from_json --template template.dcm patient.json patient.dcm
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
          "Usage: mix dcmix.from_json [--template <file>] <input_json> <output_dcm>"
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

    with {:ok, dataset} <- Dcmix.from_json_file(input_file, decode_opts),
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
