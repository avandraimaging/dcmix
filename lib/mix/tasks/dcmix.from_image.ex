defmodule Mix.Tasks.Dcmix.FromImage do
  @shortdoc "Convert image file to DICOM"

  @moduledoc """
  Converts an image file (PNG, JPEG) to DICOM format.

  Similar to dcmtk's `img2dcm`.

  ## Usage

      mix dcmix.from_image <input_image> <output_dcm>

  ## Options

      -d, --dataset-from <file>    Use DICOM file as template (copy all attributes)
      -s, --study-from <file>      Copy patient/study info from DICOM file
      -e, --series-from <file>     Copy patient/study/series info from DICOM file
      -c, --sop-class <class>      SOP class: secondary_capture (default), vl_photo
      --no-type2                   Don't auto-insert Type 2 attributes
      --no-type1                   Don't auto-generate Type 1 values

  ## Examples

      mix dcmix.from_image photo.png photo.dcm
      mix dcmix.from_image --dataset-from template.dcm photo.png photo.dcm
      mix dcmix.from_image --series-from source.dcm photo.png photo.dcm
      mix dcmix.from_image --sop-class vl_photo photo.png photo.dcm
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          dataset_from: :string,
          study_from: :string,
          series_from: :string,
          sop_class: :string,
          no_type2: :boolean,
          no_type1: :boolean
        ],
        aliases: [d: :dataset_from, s: :study_from, e: :series_from, c: :sop_class]
      )

    case files do
      [input_file, output_file] ->
        convert_file(input_file, output_file, opts)

      _ ->
        Mix.shell().error("Usage: mix dcmix.from_image [options] <input_image> <output_dcm>")
        exit({:shutdown, 1})
    end
  end

  defp convert_file(input_file, output_file, opts) do
    unless File.exists?(input_file) do
      Mix.shell().error("File not found: #{input_file}")
      exit({:shutdown, 1})
    end

    import_opts = build_import_opts(opts)

    with {:ok, dataset} <- Dcmix.from_image(input_file, import_opts),
         :ok <- Dcmix.write_file(dataset, output_file) do
      Mix.shell().info("Written to #{output_file}")
    else
      {:error, reason} ->
        Mix.shell().error("Conversion failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp build_import_opts(opts) do
    []
    |> maybe_add_dataset_from(opts)
    |> maybe_add_study_from(opts)
    |> maybe_add_series_from(opts)
    |> maybe_add_sop_class(opts)
    |> maybe_add_type_opts(opts)
  end

  defp maybe_add_dataset_from(import_opts, opts) do
    case Keyword.get(opts, :dataset_from) do
      nil -> import_opts
      path -> load_and_add(import_opts, :dataset_from, path)
    end
  end

  defp maybe_add_study_from(import_opts, opts) do
    case Keyword.get(opts, :study_from) do
      nil -> import_opts
      path -> load_and_add(import_opts, :study_from, path)
    end
  end

  defp maybe_add_series_from(import_opts, opts) do
    case Keyword.get(opts, :series_from) do
      nil -> import_opts
      path -> load_and_add(import_opts, :series_from, path)
    end
  end

  defp load_and_add(import_opts, key, path) do
    case Dcmix.read_file(path) do
      {:ok, dataset} ->
        Keyword.put(import_opts, key, dataset)

      {:error, reason} ->
        Mix.shell().error("Failed to read #{key} file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp maybe_add_sop_class(import_opts, opts) do
    case Keyword.get(opts, :sop_class) do
      nil -> import_opts
      "secondary_capture" -> Keyword.put(import_opts, :sop_class, :secondary_capture)
      "vl_photo" -> Keyword.put(import_opts, :sop_class, :vl_photo)
      other ->
        Mix.shell().error("Unknown SOP class: #{other}. Use 'secondary_capture' or 'vl_photo'.")
        exit({:shutdown, 1})
    end
  end

  defp maybe_add_type_opts(import_opts, opts) do
    import_opts
    |> maybe_add_opt(:insert_type2, not Keyword.get(opts, :no_type2, false))
    |> maybe_add_opt(:invent_type1, not Keyword.get(opts, :no_type1, false))
  end

  defp maybe_add_opt(import_opts, _key, true), do: import_opts
  defp maybe_add_opt(import_opts, key, false), do: Keyword.put(import_opts, key, false)
end
