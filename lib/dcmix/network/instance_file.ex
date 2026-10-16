defmodule Dcmix.Network.InstanceFile do
  @moduledoc """
  Writes an instance received over the network (a C-STORE data set) to a
  Part 10 file as it arrives, so it is never held in memory whole.

  `open/3` writes the File Meta Information, generated from the instance's
  SOP Class and Instance UIDs and the accepted transfer syntax. `write/2`
  appends each data set fragment exactly as received. `close/1` finishes the
  file and `discard/1` abandons it.

  Files are named by the sanitized SOP Instance UID, with no extension, as
  dcmtk does. Each instance is written to a temporary `<name>.part` file and
  renamed once complete, so an existing file of the same name is replaced
  only by a whole instance.

  Each failure returns the C-STORE-RSP status to answer with: Cannot
  Understand when the UID can't be used as a file name, Out of Resources
  when the file can't be written.
  """

  alias Dcmix.Writer

  require Dcmix.Network.DIMSE.Status, as: Status

  @enforce_keys [:io, :path, :part_path]
  defstruct [:io, :path, :part_path]

  @type t :: %__MODULE__{io: :file.io_device(), path: Path.t(), part_path: Path.t()}

  @type instance :: %{
          sop_class_uid: String.t(),
          sop_instance_uid: String.t(),
          transfer_syntax: String.t()
        }

  @doc """
  Opens `<directory>/<name>.part` for `instance` and writes its File Meta
  Information.

  ## Options
  - `:source_ae_title` - written as Source Application Entity Title
    (0002,0016) when given
  """
  @spec open(Path.t(), instance(), keyword()) :: {:ok, t()} | {:error, non_neg_integer()}
  def open(directory, instance, opts \\ []) do
    with {:ok, name} <- filename(instance.sop_instance_uid),
         path = Path.join(directory, name),
         part_path = path <> ".part",
         {:ok, io} <- File.open(part_path, [:write, :binary, :raw]) do
      file = %__MODULE__{io: io, path: path, part_path: part_path}

      with :ok <- write(file, file_meta_header(instance, opts)), do: {:ok, file}
    else
      {:error, :invalid_filename} -> {:error, Status.cannot_understand()}
      {:error, _reason} -> {:error, Status.out_of_resources()}
    end
  end

  @doc """
  Appends a data set fragment. On failure the `.part` file is deleted.
  """
  @spec write(t(), iodata()) :: :ok | {:error, non_neg_integer()}
  def write(%__MODULE__{} = file, data) do
    case :file.write(file.io, data) do
      :ok ->
        :ok

      {:error, _reason} ->
        discard(file)
        {:error, Status.out_of_resources()}
    end
  end

  @doc """
  Closes the file and renames it from `<name>.part` to `<name>`, returning
  its path. On failure the `.part` file is deleted.
  """
  # Only a complete .part file replaces the final name, so a failed repeat of
  # an instance never destroys a good earlier copy
  @spec close(t()) :: {:ok, Path.t()} | {:error, non_neg_integer()}
  def close(%__MODULE__{} = file) do
    with :ok <- File.close(file.io),
         :ok <- File.rename(file.part_path, file.path) do
      {:ok, file.path}
    else
      {:error, _reason} ->
        _ = File.rm(file.part_path)
        {:error, Status.out_of_resources()}
    end
  end

  @doc """
  Closes and deletes the `.part` file, abandoning the instance.
  """
  @spec discard(t()) :: :ok
  def discard(%__MODULE__{} = file) do
    _ = File.close(file.io)
    _ = File.rm(file.part_path)
    :ok
  end

  defp file_meta_header(instance, opts) do
    Writer.file_meta_header(
      instance.sop_class_uid,
      instance.sop_instance_uid,
      instance.transfer_syntax,
      Keyword.take(opts, [:source_ae_title])
    )
  end

  # Mirrors DcmSCU's bit-preserving path (dcmnet/libsrc/scu.cc,
  # handleCGETSession): the file is named by the Affected SOP Instance UID
  # passed through OFStandard::sanitizeFilename(), with no modality prefix or
  # extension (those come from createStorageFilename(), used only when dcmtk
  # stores in memory first).
  #
  # Deliberately stricter than sanitizeFilename() for Windows hosts: ":" (NTFS
  # alternate data streams) and space are replaced, and names that are empty
  # or end in "." (which Windows strips; covers "." and "..") are refused, as
  # are reserved device names.
  # Valid UIDs are only [0-9.] and never end in ".", so names still match
  # dcmtk's for them.
  defp filename(uid) when is_binary(uid) do
    name =
      uid
      |> String.trim_trailing(<<0>>)
      |> String.trim()
      |> sanitize_filename()

    if name == "" or String.ends_with?(name, ".") or reserved_device_name?(name),
      do: {:error, :invalid_filename},
      else: {:ok, name}
  end

  defp filename(_uid), do: {:error, :invalid_filename}

  # Windows opens the device, not a file, for these whatever the extension
  @reserved_device_names ~w(CON PRN AUX NUL) ++
                           for(n <- 1..9, prefix <- ~w(COM LPT), do: "#{prefix}#{n}")

  defp reserved_device_name?(name) do
    [base | _] = String.split(name, ".", parts: 2)
    String.upcase(base) in @reserved_device_names
  end

  # Letters, digits, "-", ".", "@", "_"
  defp sanitize_filename(name) do
    for <<c <- name>>, into: "", do: if(filename_char?(c), do: <<c>>, else: "_")
  end

  defp filename_char?(c) when c in ?0..?9 or c in ?a..?z or c in ?A..?Z, do: true
  defp filename_char?(c), do: c in ~c"-.@_"
end
