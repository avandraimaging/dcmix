defmodule Mix.Tasks.Dcmix.Mkdir do
  @shortdoc "Write the DICOMDIR for a directory's files, like dcmtk's dcmmkdir"

  @moduledoc """
  Writes the DICOMDIR for every file under a directory, at the top of that
  directory, like dcmtk's `dcmmkdir +r`. Each file's File ID is its path under
  the directory, and a DICOMDIR already there is replaced.

  A file is left out, and named with the reason, when its path isn't a valid
  File ID, when it doesn't parse as DICOM, or when `Dcmix.Dicomdir.encode/2`
  can't refer to it. A valid File ID has one to eight components of one to
  eight characters from A-Z, 0-9 and `_` (PS3.10 §8.2, §8.5).

  ## Usage

      mix dcmix.mkdir [options] <directory>

  ## Options

      --fileset-id  File-set ID (0004,1130): up to 16 characters from A-Z,
                    0-9, space and `_` (default: empty)

  ## Examples

      mix dcmix.mkdir media
      mix dcmix.mkdir --fileset-id STUDY_01 media
  """

  use Mix.Task

  @file_id_component ~r/\A[A-Z0-9_]{1,8}\z/
  @file_set_id ~r/\A[A-Z0-9_ ]{0,16}\z/
  @lacks_uid "it lacks a UID its record needs"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, strict: [fileset_id: :string])

    case positional do
      [directory | _] -> make(directory, opts)
      [] -> fail("Usage: mix dcmix.mkdir [options] <directory>")
    end
  end

  defp make(directory, opts) do
    file_set_id = Keyword.get(opts, :fileset_id, "")
    unless File.dir?(directory), do: fail("Not a directory: #{directory}")

    unless Regex.match?(@file_set_id, file_set_id),
      do: fail("Not a valid File-set ID: #{file_set_id}")

    instances =
      directory
      |> files([])
      |> Enum.reject(&(&1 == ["DICOMDIR"]))
      |> Enum.map(&instance(directory, &1))
      |> Enum.reject(&is_nil/1)

    case Dcmix.Dicomdir.encode(instances, file_set_id: file_set_id) do
      {:ok, dicomdir, left_out} ->
        Enum.each(left_out, &left_out(directory, &1, @lacks_uid))
        path = Path.join(directory, "DICOMDIR")
        File.write!(path, dicomdir)
        referred = length(instances) - length(left_out)
        Mix.shell().info("Wrote #{path}, referring to #{referred} instance(s)")

      # Every instance it was given was refused.
      {:error, :no_instances} ->
        Enum.each(instances, fn {file_id, _data_set} ->
          left_out(directory, file_id, @lacks_uid)
        end)

        fail("Nothing under #{directory} can go in a DICOMDIR")
    end
  end

  # Each file's path components under `directory`, sorted so the records come
  # out in the same order on every run.
  defp files(directory, components) do
    [directory | components]
    |> Path.join()
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      file_id = components ++ [name]

      if File.dir?(Path.join([directory | file_id])),
        do: files(directory, file_id),
        else: [file_id]
    end)
  end

  defp instance(directory, file_id) do
    if file_id?(file_id) do
      case Dcmix.read_file(Path.join([directory | file_id]), stop_before_pixels: true) do
        {:ok, data_set} -> {file_id, data_set}
        {:error, _reason} -> left_out(directory, file_id, "it doesn't parse as DICOM")
      end
    else
      left_out(directory, file_id, "its path isn't a valid File ID")
    end
  end

  defp file_id?(file_id),
    do: length(file_id) <= 8 and Enum.all?(file_id, &Regex.match?(@file_id_component, &1))

  defp left_out(directory, file_id, reason) do
    Mix.shell().error("Left out #{Path.join([directory | file_id])}: #{reason}")
    nil
  end

  defp fail(message) do
    Mix.shell().error(message)
    exit({:shutdown, 1})
  end
end
