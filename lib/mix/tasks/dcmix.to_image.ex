defmodule Mix.Tasks.Dcmix.ToImage do
  @shortdoc "Convert DICOM file to an image (PNG, PPM, PGM)"

  @moduledoc """
  Exports DICOM pixel data to an image file.

  Similar to dcmtk's `dcm2pnm` and dicom-rs's `dicom-toimage`.

  ## Usage

      mix dcmix.to_image <input_file> <output_file>

  The output format is inferred from the file extension (.png, .ppm, .pgm).

  ## Options

      --frame, -f <n>           Frame number for multi-frame images (0-indexed, default: 0)
      --window, -w <spec>       Windowing for grayscale: auto, min_max, none, or center,width
      --format <format>         Force output format: png, ppm, or pgm

  ## Examples

      mix dcmix.to_image patient.dcm patient.png
      mix dcmix.to_image --frame 0 patient.dcm patient.png
      mix dcmix.to_image --window auto patient.dcm patient.png
      mix dcmix.to_image --window 400,40 patient.dcm patient.png
      mix dcmix.to_image --format pgm patient.dcm output.raw

  ## Windowing

  Windowing is used to map 12-bit or 16-bit grayscale values to 8-bit for display:

  - `auto` - Use VOI LUT from DICOM tags if available, else use min/max (default)
  - `min_max` - Window based on actual min/max pixel values in the image
  - `none` - No windowing, preserve raw values (may require 16-bit output)
  - `center,width` - Explicit window center and width (e.g., `400,40` for CT soft tissue)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [frame: :integer, window: :string, format: :string],
        aliases: [f: :frame, w: :window]
      )

    case files do
      [] ->
        Mix.shell().error("Usage: mix dcmix.to_image <input_file> <output_file>")
        exit({:shutdown, 1})

      [_input_file] ->
        Mix.shell().error("Usage: mix dcmix.to_image <input_file> <output_file>")
        exit({:shutdown, 1})

      [input_file, output_file | _] ->
        convert_file(input_file, output_file, opts)
    end
  end

  defp convert_file(input_file, output_file, opts) do
    unless File.exists?(input_file) do
      Mix.shell().error("File not found: #{input_file}")
      exit({:shutdown, 1})
    end

    image_opts = build_options(opts)

    with {:ok, dataset} <- Dcmix.read_file(input_file),
         :ok <- Dcmix.to_image(dataset, output_file, image_opts) do
      Mix.shell().info("Written to #{output_file}")
    else
      {:error, {:compressed_pixel_data, message}} ->
        Mix.shell().error("Error: #{message}")
        exit({:shutdown, 1})

      {:error, {:unsupported_photometric, message}} ->
        Mix.shell().error("Error: #{message}")
        exit({:shutdown, 1})

      {:error, {:missing_required_field, field}} ->
        Mix.shell().error("Error: Missing required DICOM tag: #{field}")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Conversion failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp build_options(opts) do
    []
    |> add_frame_option(opts)
    |> add_window_option(opts)
    |> add_format_option(opts)
  end

  defp add_frame_option(image_opts, opts) do
    case Keyword.get(opts, :frame) do
      nil -> image_opts
      frame -> Keyword.put(image_opts, :frame, frame)
    end
  end

  defp add_window_option(image_opts, opts) do
    case Keyword.get(opts, :window) do
      nil -> image_opts
      "auto" -> Keyword.put(image_opts, :window, :auto)
      "min_max" -> Keyword.put(image_opts, :window, :min_max)
      "none" -> Keyword.put(image_opts, :window, :none)
      spec -> parse_window_spec(image_opts, spec)
    end
  end

  defp parse_window_spec(image_opts, spec) do
    case String.split(spec, ",") do
      [center_str, width_str] ->
        case {Float.parse(center_str), Float.parse(width_str)} do
          {{center, ""}, {width, ""}} ->
            Keyword.put(image_opts, :window, {center, width})

          _ ->
            Mix.shell().error("Invalid window specification: #{spec}")
            Mix.shell().error("Use: center,width (e.g., 400,40)")
            exit({:shutdown, 1})
        end

      _ ->
        Mix.shell().error("Invalid window specification: #{spec}")
        Mix.shell().error("Use: auto, min_max, none, or center,width")
        exit({:shutdown, 1})
    end
  end

  defp add_format_option(image_opts, opts) do
    case Keyword.get(opts, :format) do
      nil ->
        image_opts

      "png" ->
        Keyword.put(image_opts, :format, :png)

      "ppm" ->
        Keyword.put(image_opts, :format, :ppm)

      "pgm" ->
        Keyword.put(image_opts, :format, :pgm)

      other ->
        Mix.shell().error("Unknown format: #{other}")
        Mix.shell().error("Supported formats: png, ppm, pgm")
        exit({:shutdown, 1})
    end
  end
end
