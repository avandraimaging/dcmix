defmodule Mix.Dcmix.NetworkCLI do
  @moduledoc """
  Shared argument handling for dcmix's mix tasks that mirror dcmtk's network
  tools (`mix dcmix.echoscu`, `mix dcmix.findscu`, `mix dcmix.getscu`,
  `mix dcmix.movescu`).

  The tasks take dcmtk's long option names (`--aetitle`, `--call`, `--key`,
  ...). dcmtk's single-dash short flags (`-aet`, `-aec`, `-k`, ...) are
  translated to those first, so a dcmtk command line works with the tool's
  name swapped for the mix task.
  """

  alias Dcmix.{DataSet, Dictionary, Tag}

  # dcmtk's multi-letter short flags, which OptionParser can't read
  @dcmtk_flags %{
    "-aet" => "--aetitle",
    "-aec" => "--call",
    "-aem" => "--move",
    "-od" => "--output-directory",
    "-to" => "--timeout",
    "-ta" => "--acse-timeout",
    "-td" => "--dimse-timeout",
    "-pdu" => "--max-pdu"
  }

  # Options every network task takes
  @connection_switches [
    aetitle: :string,
    call: :string,
    timeout: :integer,
    acse_timeout: :integer,
    dimse_timeout: :integer,
    max_pdu: :integer,
    verbose: :boolean
  ]

  @doc """
  Translates dcmtk's multi-letter short flags to their long names, leaving
  everything else alone.

      iex> Mix.Dcmix.NetworkCLI.translate_flags(["-aet", "ME", "-aec", "PACS", "-k", "PatientID=1", "pacs", "104"])
      ["--aetitle", "ME", "--call", "PACS", "-k", "PatientID=1", "pacs", "104"]

      iex> Mix.Dcmix.NetworkCLI.translate_flags(["-od", "out", "-td", "30"])
      ["--output-directory", "out", "--dimse-timeout", "30"]
  """
  @spec translate_flags([String.t()]) :: [String.t()]
  def translate_flags(args), do: Enum.map(args, &Map.get(@dcmtk_flags, &1, &1))

  @doc """
  Parses a task's arguments: dcmtk's short flags are translated, then the
  common connection options and `extra_switches` are read, with `-v`, `-k`,
  `-P` and `-S` as aliases. Returns `{:ok, opts, positional}` or
  `{:error, message}` naming the first unknown or malformed option.

      iex> Mix.Dcmix.NetworkCLI.parse(["-aet", "ME", "-v", "pacs", "104"])
      {:ok, [aetitle: "ME", verbose: true], ["pacs", "104"]}

      iex> Mix.Dcmix.NetworkCLI.parse(["--bogus", "pacs", "104"])
      {:error, "unknown option --bogus"}
  """
  @spec parse([String.t()], keyword()) :: {:ok, keyword(), [String.t()]} | {:error, String.t()}
  def parse(args, extra_switches \\ []) do
    {opts, positional, invalid} =
      args
      |> translate_flags()
      |> OptionParser.parse(
        strict: @connection_switches ++ extra_switches,
        aliases: [v: :verbose, k: :key, P: :patient, S: :study]
      )

    case invalid do
      [] -> {:ok, opts, positional}
      [{option, nil} | _] -> {:error, "unknown option #{option}"}
      [{option, value} | _] -> {:error, "invalid value #{inspect(value)} for #{option}"}
    end
  end

  @doc """
  The peer's address from the `peer port` positional arguments.

      iex> Mix.Dcmix.NetworkCLI.peer(["pacs", "104"])
      {:ok, "pacs:104"}

      iex> Mix.Dcmix.NetworkCLI.peer(["pacs"])
      {:error, "expected the peer and port, e.g. localhost 4242"}
  """
  @spec peer([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def peer([host, port | _]) do
    case Integer.parse(port) do
      {_port, ""} -> {:ok, "#{host}:#{port}"}
      _ -> {:error, "invalid port #{inspect(port)}"}
    end
  end

  def peer(_positional), do: {:error, "expected the peer and port, e.g. localhost 4242"}

  @doc """
  The dcmix connection options for the parsed options. Timeouts are given in
  seconds, as dcmtk takes them; dcmix has one timeout for every read, so the
  DIMSE timeout wins, then the ACSE timeout, then `--timeout`.

      iex> Mix.Dcmix.NetworkCLI.connection_opts(aetitle: "ME", call: "PACS", dimse_timeout: 30, timeout: 5)
      [calling_ae_title: "ME", called_ae_title: "PACS", timeout: 30_000]

      iex> Mix.Dcmix.NetworkCLI.connection_opts([])
      []
  """
  @spec connection_opts(keyword()) :: keyword()
  def connection_opts(opts) do
    timeout = opts[:dimse_timeout] || opts[:acse_timeout] || opts[:timeout]

    [
      calling_ae_title: opts[:aetitle],
      called_ae_title: opts[:call],
      timeout: timeout && timeout * 1_000,
      max_pdu_length: opts[:max_pdu],
      verbose: opts[:verbose]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  The query model from `--patient` (`-P`) or `--study` (`-S`); Study Root
  when neither is given, as in dcmix.

      iex> Mix.Dcmix.NetworkCLI.query_model(patient: true)
      :patient_root

      iex> Mix.Dcmix.NetworkCLI.query_model([])
      :study_root
  """
  @spec query_model(keyword()) :: :patient_root | :study_root
  def query_model(opts), do: if(opts[:patient], do: :patient_root, else: :study_root)

  @doc """
  Builds a query or retrieve identifier from `--key` values, as dcmtk's `-k`:
  `Keyword=value` or `(gggg,eeee)=value` (the parentheses are optional), the
  VR taken from the dictionary. An empty value asks for the key to be
  returned.

      iex> {:ok, ds} = Mix.Dcmix.NetworkCLI.identifier(["QueryRetrieveLevel=STUDY", "(0010,0020)=", "0020,000D=1.2.3"])
      iex> {Dcmix.DataSet.get_string(ds, {0x0008, 0x0052}), Dcmix.DataSet.get_string(ds, {0x0010, 0x0020}), Dcmix.DataSet.get_string(ds, {0x0020, 0x000D})}
      {"STUDY", "", "1.2.3"}

      iex> Mix.Dcmix.NetworkCLI.identifier(["NotAKeyword=1"])
      {:error, "unknown key NotAKeyword"}

      iex> Mix.Dcmix.NetworkCLI.identifier(["PatientID"])
      {:error, "expected a key as Keyword=value, got \\"PatientID\\""}
  """
  @spec identifier([String.t()]) :: {:ok, DataSet.t()} | {:error, String.t()}
  def identifier(keys) do
    Enum.reduce_while(keys, {:ok, DataSet.new()}, fn key, {:ok, ds} ->
      case put_key(ds, key) do
        {:ok, ds} -> {:cont, {:ok, ds}}
        error -> {:halt, error}
      end
    end)
  end

  defp put_key(ds, key) do
    with [name, value] <- String.split(key, "=", parts: 2),
         {:ok, %{tag: tag, vr: vr}} <- lookup(String.trim(name)) do
      {:ok, DataSet.put_element(ds, tag, vr, value)}
    else
      [_no_equals] -> {:error, "expected a key as Keyword=value, got #{inspect(key)}"}
      {:error, name} -> {:error, "unknown key #{name}"}
    end
  end

  defp lookup(name) do
    with {:ok, tag} <- tag(name),
         {:ok, entry} <- Dictionary.lookup(tag) do
      {:ok, entry}
    else
      _ -> {:error, name}
    end
  end

  # (gggg,eeee), gggg,eeee, or a dictionary keyword
  defp tag(name) do
    cond do
      String.match?(name, ~r/^[0-9A-Fa-f]{4},[0-9A-Fa-f]{4}$/) -> Tag.parse("(#{name})")
      String.starts_with?(name, "(") -> Tag.parse(name)
      true -> with {:ok, %{tag: tag}} <- Dictionary.lookup_keyword(name), do: {:ok, tag}
    end
  end

  @doc """
  A DIMSE status as dcmtk prints it, e.g. `0x0000`.

      iex> Mix.Dcmix.NetworkCLI.status(0xB000)
      "0xB000"
  """
  @spec status(non_neg_integer() | nil) :: String.t()
  def status(nil), do: "none"
  def status(code), do: "0x" <> String.pad_leading(Integer.to_string(code, 16), 4, "0")

  @doc """
  Prints `message` as an error and stops the task with exit status 1.
  """
  @spec fail!(String.t()) :: no_return()
  def fail!(message) do
    Mix.shell().error(message)
    exit({:shutdown, 1})
  end
end
