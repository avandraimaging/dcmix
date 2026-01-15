defmodule Dcmix.Parser.TransferSyntax do
  @moduledoc """
  DICOM Transfer Syntax definitions and utilities.

  A Transfer Syntax defines how DICOM data is encoded, including:
  - Whether VR is explicit or implicit
  - Byte ordering (little-endian or big-endian)
  - Whether pixel data is compressed
  """

  @type t :: %__MODULE__{
          uid: String.t(),
          name: String.t(),
          explicit_vr: boolean(),
          big_endian: boolean(),
          encapsulated: boolean(),
          lossy: boolean()
        }

  defstruct [:uid, :name, :explicit_vr, :big_endian, :encapsulated, :lossy]

  # Standard Transfer Syntaxes UIDs
  @implicit_vr_little_endian "1.2.840.10008.1.2"
  @explicit_vr_little_endian "1.2.840.10008.1.2.1"
  @explicit_vr_big_endian "1.2.840.10008.1.2.2"

  # Compressed Transfer Syntaxes UIDs
  @jpeg_baseline "1.2.840.10008.1.2.4.50"
  @jpeg_extended "1.2.840.10008.1.2.4.51"
  @jpeg_lossless "1.2.840.10008.1.2.4.57"
  @jpeg_lossless_sv1 "1.2.840.10008.1.2.4.70"
  @jpeg_ls_lossless "1.2.840.10008.1.2.4.80"
  @jpeg_ls_lossy "1.2.840.10008.1.2.4.81"
  @jpeg_2000_lossless "1.2.840.10008.1.2.4.90"
  @jpeg_2000 "1.2.840.10008.1.2.4.91"
  @rle_lossless "1.2.840.10008.1.2.5"

  # UID accessors
  def implicit_vr_little_endian, do: @implicit_vr_little_endian
  def explicit_vr_little_endian, do: @explicit_vr_little_endian
  def explicit_vr_big_endian, do: @explicit_vr_big_endian
  def jpeg_baseline, do: @jpeg_baseline
  def jpeg_extended, do: @jpeg_extended
  def jpeg_lossless, do: @jpeg_lossless
  def jpeg_lossless_sv1, do: @jpeg_lossless_sv1
  def jpeg_ls_lossless, do: @jpeg_ls_lossless
  def jpeg_ls_lossy, do: @jpeg_ls_lossy
  def jpeg_2000_lossless, do: @jpeg_2000_lossless
  def jpeg_2000, do: @jpeg_2000
  def rle_lossless, do: @rle_lossless

  # Build transfer syntax map at runtime
  defp transfer_syntaxes do
    %{
      @implicit_vr_little_endian => %__MODULE__{
        uid: @implicit_vr_little_endian,
        name: "Implicit VR Little Endian",
        explicit_vr: false,
        big_endian: false,
        encapsulated: false,
        lossy: false
      },
      @explicit_vr_little_endian => %__MODULE__{
        uid: @explicit_vr_little_endian,
        name: "Explicit VR Little Endian",
        explicit_vr: true,
        big_endian: false,
        encapsulated: false,
        lossy: false
      },
      @explicit_vr_big_endian => %__MODULE__{
        uid: @explicit_vr_big_endian,
        name: "Explicit VR Big Endian (Retired)",
        explicit_vr: true,
        big_endian: true,
        encapsulated: false,
        lossy: false
      },
      @jpeg_baseline => %__MODULE__{
        uid: @jpeg_baseline,
        name: "JPEG Baseline (Process 1)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: true
      },
      @jpeg_extended => %__MODULE__{
        uid: @jpeg_extended,
        name: "JPEG Extended (Process 2 & 4)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: true
      },
      @jpeg_lossless => %__MODULE__{
        uid: @jpeg_lossless,
        name: "JPEG Lossless (Process 14)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: false
      },
      @jpeg_lossless_sv1 => %__MODULE__{
        uid: @jpeg_lossless_sv1,
        name: "JPEG Lossless (Process 14, SV1)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: false
      },
      @jpeg_ls_lossless => %__MODULE__{
        uid: @jpeg_ls_lossless,
        name: "JPEG-LS Lossless",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: false
      },
      @jpeg_ls_lossy => %__MODULE__{
        uid: @jpeg_ls_lossy,
        name: "JPEG-LS Lossy (Near-Lossless)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: true
      },
      @jpeg_2000_lossless => %__MODULE__{
        uid: @jpeg_2000_lossless,
        name: "JPEG 2000 Image Compression (Lossless Only)",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: false
      },
      @jpeg_2000 => %__MODULE__{
        uid: @jpeg_2000,
        name: "JPEG 2000 Image Compression",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: true
      },
      @rle_lossless => %__MODULE__{
        uid: @rle_lossless,
        name: "RLE Lossless",
        explicit_vr: true,
        big_endian: false,
        encapsulated: true,
        lossy: false
      }
    }
  end

  @doc """
  Looks up a transfer syntax by UID.

  ## Examples

      iex> Dcmix.Parser.TransferSyntax.lookup("1.2.840.10008.1.2.1")
      {:ok, %Dcmix.Parser.TransferSyntax{name: "Explicit VR Little Endian", ...}}
  """
  @spec lookup(String.t()) :: {:ok, t()} | {:error, :unknown_transfer_syntax}
  def lookup(uid) do
    case Map.get(transfer_syntaxes(), uid) do
      nil -> {:error, :unknown_transfer_syntax}
      ts -> {:ok, ts}
    end
  end

  @doc """
  Returns the default transfer syntax (Explicit VR Little Endian).
  """
  @spec default() :: t()
  def default, do: Map.get(transfer_syntaxes(), @explicit_vr_little_endian)

  @doc """
  Returns true if the transfer syntax uses explicit VR.
  """
  @spec explicit_vr?(t() | String.t()) :: boolean()
  def explicit_vr?(%__MODULE__{explicit_vr: explicit_vr}), do: explicit_vr

  def explicit_vr?(uid) when is_binary(uid) do
    case lookup(uid) do
      {:ok, ts} -> ts.explicit_vr
      {:error, _} -> true
    end
  end

  @doc """
  Returns true if the transfer syntax uses big-endian byte ordering.
  """
  @spec big_endian?(t() | String.t()) :: boolean()
  def big_endian?(%__MODULE__{big_endian: big_endian}), do: big_endian

  def big_endian?(uid) when is_binary(uid) do
    case lookup(uid) do
      {:ok, ts} -> ts.big_endian
      {:error, _} -> false
    end
  end

  @doc """
  Returns true if the transfer syntax uses encapsulated (compressed) pixel data.
  """
  @spec encapsulated?(t() | String.t()) :: boolean()
  def encapsulated?(%__MODULE__{encapsulated: encapsulated}), do: encapsulated

  def encapsulated?(uid) when is_binary(uid) do
    case lookup(uid) do
      {:ok, ts} -> ts.encapsulated
      {:error, _} -> false
    end
  end

  @doc """
  Returns true if the transfer syntax is lossy.
  """
  @spec lossy?(t() | String.t()) :: boolean()
  def lossy?(%__MODULE__{lossy: lossy}), do: lossy

  def lossy?(uid) when is_binary(uid) do
    case lookup(uid) do
      {:ok, ts} -> ts.lossy
      {:error, _} -> false
    end
  end

  @doc """
  Returns all known transfer syntaxes.
  """
  @spec all() :: [t()]
  def all, do: Map.values(transfer_syntaxes())
end
