defmodule Dcmix.Network.ListenerTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network
  alias Dcmix.Network.{Association, DIMSE, Listener, PDU, SOPClassUID}
  alias Dcmix.Parser.TransferSyntax

  require Dcmix.Network.DIMSE.Status, as: Status
  require Dcmix.Network.PDU.AssociateRJ, as: AssociateRJ
  require Dcmix.Network.PDU.PresentationContextResult, as: ContextResult

  @moduletag capture_log: true

  defp start_listener(opts \\ []) do
    listener = start_supervised!({Listener, Keyword.merge([port: 0, ae_title: "SCP"], opts)})
    {:ok, port} = Listener.port(listener)
    "localhost:#{port}"
  end

  defp open(addr, abstract_syntax \\ SOPClassUID.verification()) do
    Association.request(addr,
      called_ae_title: "SCP",
      abstract_syntaxes: [abstract_syntax],
      transfer_syntaxes: [TransferSyntax.implicit_vr_little_endian()],
      timeout: 5_000
    )
  end

  describe "C-ECHO" do
    test "answers a C-ECHO with success" do
      assert Network.echo(start_listener(), called_ae_title: "SCP") == :ok
    end

    test "answers every C-ECHO on an association" do
      {:ok, assoc} = open(start_listener())
      {:ok, pc} = Association.accepted_context(assoc)

      for message_id <- [1, 2] do
        :ok = Association.send_pdata(assoc, pc.id, true, DIMSE.build_cecho_rq(message_id))
        assert {:ok, command} = receive_command(assoc)
        assert command.message_id_being_responded_to == message_id
        assert command.status == Status.success()
      end

      Association.release(assoc)
    end

    test "reads a C-ECHO-RQ split across PDVs" do
      {:ok, assoc} = open(start_listener())
      {:ok, pc} = Association.accepted_context(assoc)
      <<first::binary-size(10), rest::binary>> = DIMSE.build_cecho_rq(9)

      send_raw(assoc, PDU.encode_p_data(pc.id, true, false, first))
      send_raw(assoc, PDU.encode_p_data(pc.id, true, true, rest))

      assert {:ok, %{message_id_being_responded_to: 9, status: Status.success()}} =
               receive_command(assoc)

      Association.release(assoc)
    end

    test "serves associations concurrently" do
      addr = start_listener()

      results =
        1..5
        |> Task.async_stream(fn _ -> Network.echo(addr, called_ae_title: "SCP") end)
        |> Enum.map(fn {:ok, result} -> result end)

      assert results == List.duplicate(:ok, 5)
    end
  end

  describe "negotiation" do
    test "rejects a called AE title other than ours" do
      assert {:error, {:association_rejected, result, reason}} =
               Network.echo(start_listener(), called_ae_title: "OTHER")

      assert result == AssociateRJ.rejected_permanent()
      assert reason == AssociateRJ.service_user_called_ae_title_not_recognized()
    end

    test "accepts the association but not a context for an unsupported SOP Class" do
      {:ok, assoc} = open(start_listener(), SOPClassUID.study_root_query_retrieve_find())

      assert [%{result: ContextResult.abstract_syntax_not_supported()}] =
               assoc.presentation_contexts

      assert Association.accepted_context(assoc) == {:error, :no_accepted_presentation_context}
      Association.release(assoc)
    end

    test "accepts an A-ASSOCIATE-RQ larger than 64 KiB" do
      addr = start_listener()
      padding = :binary.copy(<<0>>, 40_000)
      unknown_item = <<0x60, 0x00, byte_size(padding)::16-big, padding::binary>>
      rq = PDU.encode_associate_rq("SCU", "SCP", [verification_context()])
      <<0x01, 0x00, length::32-big, payload::binary>> = rq
      big_rq = <<0x01, 0x00, length + 2 * byte_size(unknown_item)::32-big, payload::binary>>

      socket = connect(addr)
      :ok = :gen_tcp.send(socket, [big_rq, unknown_item, unknown_item])

      assert {:ok, <<0x02, _::binary>>} = :gen_tcp.recv(socket, 0, 5_000)
      :gen_tcp.close(socket)
    end
  end

  describe "max_associations" do
    test "rejects an association beyond the limit, then accepts once one ends" do
      addr = start_listener(max_associations: 1)
      {:ok, held} = open(addr)

      assert {:error, {:association_rejected, result, reason}} =
               Network.echo(addr, called_ae_title: "SCP")

      assert result == AssociateRJ.rejected_transient()
      assert reason == AssociateRJ.presentation_local_limit_exceeded()

      Association.release(held)
      assert eventually(fn -> Network.echo(addr, called_ae_title: "SCP") == :ok end)
    end
  end

  describe "ending an association" do
    test "answers an A-RELEASE-RQ with an A-RELEASE-RP" do
      {:ok, assoc} = open(start_listener())

      send_raw(assoc, PDU.encode_release_rq())
      assert Association.receive_pdu(assoc, 5_000) == {:ok, :release_rp}
      assert {:error, {:recv_failed, :closed}} = Association.receive_pdu(assoc, 5_000)
    end

    test "keeps serving after a requestor aborts" do
      addr = start_listener()
      {:ok, assoc} = open(addr)
      Association.abort(assoc)

      assert Network.echo(addr, called_ae_title: "SCP") == :ok
    end

    test "aborts an association that stays idle past the timeout" do
      {:ok, assoc} = open(start_listener(timeout: 100))
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end
  end

  describe "aborts on a requestor's protocol errors" do
    test "a command other than C-ECHO" do
      {:ok, assoc} = open(start_listener())
      {:ok, pc} = Association.accepted_context(assoc)

      :ok =
        Association.send_pdata(
          assoc,
          pc.id,
          true,
          DIMSE.build_cfind_rq(SOPClassUID.verification(), 1)
        )

      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end

    test "a presentation context that wasn't accepted" do
      {:ok, assoc} = open(start_listener())

      :ok = Association.send_pdata(assoc, 99, true, DIMSE.build_cecho_rq(1))
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end

    test "a data set where a command is expected" do
      {:ok, assoc} = open(start_listener())
      {:ok, pc} = Association.accepted_context(assoc)

      :ok = Association.send_pdata(assoc, pc.id, false, <<0, 0, 0, 0>>)
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end

    test "a command that doesn't decode" do
      {:ok, assoc} = open(start_listener())
      {:ok, pc} = Association.accepted_context(assoc)

      :ok = Association.send_pdata(assoc, pc.id, true, <<0, 0, 0>>)
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end

    test "an A-ASSOCIATE-RQ in an established association" do
      {:ok, assoc} = open(start_listener())

      send_raw(assoc, PDU.encode_associate_rq("SCU", "SCP", [verification_context()]))
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end

    test "a first PDU that isn't an A-ASSOCIATE-RQ" do
      socket = connect(start_listener())
      :ok = :gen_tcp.send(socket, PDU.encode_release_rq())

      assert {:ok, <<0x07, _::binary>>} = :gen_tcp.recv(socket, 0, 5_000)
      :gen_tcp.close(socket)
    end

    test "an A-ASSOCIATE-RQ over 1 MiB, without reading it" do
      socket = connect(start_listener())
      :ok = :gen_tcp.send(socket, <<0x01, 0x00, 1_048_577::32-big>>)

      assert {:ok, <<0x07, _::binary>>} = :gen_tcp.recv(socket, 0, 5_000)
      :gen_tcp.close(socket)
    end

    test "an A-ASSOCIATE-RQ that doesn't decode" do
      socket = connect(start_listener())
      :ok = :gen_tcp.send(socket, <<0x01, 0x00, 4::32-big, 0::32>>)

      assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
    end
  end

  describe "start_link/1" do
    test "requires a port and an AE title" do
      assert_raise KeyError, fn -> Listener.start_link(ae_title: "SCP") end
      assert_raise KeyError, fn -> Listener.start_link(port: 0) end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, fn ->
        Listener.start_link(port: 0, ae_title: "SCP", bogus: 1)
      end
    end
  end

  defp verification_context,
    do: %{
      id: 1,
      abstract_syntax: SOPClassUID.verification(),
      transfer_syntaxes: [TransferSyntax.implicit_vr_little_endian()]
    }

  defp connect(addr) do
    [host, port] = String.split(addr, ":")

    {:ok, socket} =
      :gen_tcp.connect(String.to_charlist(host), String.to_integer(port), [
        :binary,
        active: false
      ])

    socket
  end

  defp send_raw(assoc, pdu), do: :ok = :gen_tcp.send(assoc.socket, pdu)

  defp receive_command(assoc) do
    {:ok, {:p_data, [pdv]}} = Association.receive_pdu(assoc, 5_000)
    DIMSE.decode_command(pdv.data)
  end

  # The listener counts an association as ended once its process does, just
  # after the requestor sees the release
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
