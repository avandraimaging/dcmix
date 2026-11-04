# Regenerates priv/dictionary/dicom.dic from the DICOM Standard's data
# dictionary (PS3.6), so a refresh is one run:
#
#     mise run dictionary                     # downloads the current PS3.6
#     mise run dictionary -- path/part06.xml  # or reads a copy already on disk
#
# It reads every data element registry table in PS3.6's DocBook source, retired
# and repeating-group entries included, and leaves out entries with no keyword.
# A tag PS3.6 gives more than one VR gets the VR implicit VR data is read with:
# OW for "OB or OW", as PS3.5 encodes those in implicit VR, otherwise the first
# VR listed, with the VM listed first. SV, UV and OV, which dcmix doesn't
# support yet, are written as UN.

defmodule GenerateDictionary do
  @source_url "https://dicom.nema.org/medical/dicom/current/source/docbook/part06/part06.xml"
  @output_path "priv/dictionary/dicom.dic"

  # Data Elements, File Meta Elements, Directory Structuring Elements and
  # Dynamic RTP Payload Elements.
  @tables ["table_6-1", "table_7-1", "table_8-1", "table_9-1"]

  # 64-bit VRs Dcmix.VR doesn't define yet; their tags read as UN, as they did
  # before the dictionary knew them.
  @unsupported_vrs ["SV", "UV", "OV"]

  def run(args) do
    xml = read_source(args)
    edition = edition(xml)

    {entries, skipped} =
      @tables
      |> Enum.flat_map(&table_rows(xml, &1))
      |> Enum.map(&entry/1)
      |> Enum.split_with(&(&1.keyword != ""))

    File.write!(@output_path, render(entries, edition))

    IO.puts(
      "Wrote #{length(entries)} entries from DICOM PS3.6 #{edition} to #{@output_path}; " <>
        "left out #{length(skipped)} with no keyword"
    )
  end

  defp read_source([path]), do: File.read!(path)

  defp read_source([]) do
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    # NEMA's server speaks TLS 1.2 only, and offers a Diffie-Hellman key exchange
    # OTP refuses as too weak and ECDHE only with CBC ciphers, which OTP's
    # defaults leave out.
    ecdhe =
      :ssl.cipher_suites(:all, :"tlsv1.2")
      |> :ssl.filter_cipher_suites(key_exchange: &(&1 in [:ecdhe_rsa, :ecdhe_ecdsa]))

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      versions: [:"tlsv1.2"],
      ciphers: ecdhe,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {@source_url, []}, [ssl: ssl, timeout: 120_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> body
      other -> raise "couldn't download #{@source_url}: #{inspect(other)}"
    end
  end

  defp edition(xml) do
    case Regex.run(~r/DICOM PS3\.6 (\d{4}[a-z])/, xml) do
      [_match, edition] -> edition
      nil -> raise "couldn't find PS3.6's edition in its source"
    end
  end

  defp table_rows(xml, id) do
    [_before, rest] = String.split(xml, ~s(xml:id="#{id}"), parts: 2)
    [table, _after] = String.split(rest, "</table>", parts: 2)
    [_head, body] = String.split(table, "<tbody>", parts: 2)

    ~r{<tr[^>]*>(.*?)</tr>}s
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn [row] ->
      Regex.scan(~r{<td[^>]*>(.*?)</td>}s, row, capture: :all_but_first)
      |> Enum.map(fn [cell] -> cell_text(cell) end)
    end)
  end

  defp cell_text(cell) do
    cell
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("\u200B", "")
    |> String.replace("&apos;", "'")
    |> String.replace("&quot;", "\"")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.split()
    |> Enum.join(" ")
  end

  defp entry([tag, name, keyword, vr, vm | _retired]) do
    [_match, group, element] = Regex.run(~r/^\(([0-9A-Fa-fx]{4}),([0-9A-Fa-fx]{4})\)$/, tag)

    %{
      group: tag_part(group),
      element: tag_part(element),
      name: name,
      keyword: keyword,
      vr: implicit_vr(vr),
      vm: multiplicity(vm)
    }
  end

  # LUTData and GrayLookupTableData have a VM per VR, "1-n or 1"; the first goes
  # with the first VR.
  defp multiplicity(""), do: "1"
  defp multiplicity(vm), do: vm |> String.split(" or ") |> hd()

  # Hex digits upper case, a repeating group's x lower case, as PS3.6 writes it.
  defp tag_part(part), do: part |> String.upcase() |> String.replace("X", "x")

  defp implicit_vr(vr) do
    vrs = Regex.scan(~r/\b[A-Z]{2}\b/, vr) |> List.flatten()

    cond do
      vrs == [] -> "NONE"
      "OB" in vrs and "OW" in vrs -> "OW"
      hd(vrs) in @unsupported_vrs -> "UN"
      true -> hd(vrs)
    end
  end

  defp render(entries, edition) do
    header = """
    # DICOM Data Dictionary
    # Format: group element VR keyword VM description
    # Generated from DICOM PS3.6 #{edition} by scripts/generate_dictionary.exs;
    # run `mise run dictionary` to refresh it rather than editing it by hand.
    # x in a group or element matches any hex digit (repeating groups).
    """

    lines =
      Enum.map(entries, fn e ->
        Enum.join([e.group, e.element, e.vr, e.keyword, e.vm, e.name], " ")
      end)

    header <> Enum.join(lines, "\n") <> "\n"
  end
end

GenerateDictionary.run(System.argv())
