defmodule Dcmix.Network.CEchoTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network
  alias Dcmix.Network.{CEcho, DIMSE}

  @implicit_vr_le "1.2.840.10008.1.2"
  @verification "1.2.840.10008.1.1"

  describe "echo/2" do
    test "returns :ok when the SCP answers with success" do
      port = start_scp(self(), associate_ac(0), [echo_rsp(0x0000)])

      assert :ok =
               CEcho.echo("127.0.0.1:#{port}",
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      assert_receive {:associate_rq, rq}
      assert :binary.match(rq, @verification) != :nomatch

      assert_receive {:command, command}
      assert {:ok, %{command_field: 0x0030, message_id: 1}} = DIMSE.decode_command(command)
      assert_receive :released
    end

    test "reads a response command split across PDUs" do
      <<0x04, 0x00, _len::32-big, _pdv_len::32-big, 1, 0x03, command::binary>> =
        echo_rsp(0x0000)

      <<first::binary-size(10), rest::binary>> = command
      port = start_scp(self(), associate_ac(0), [pdata(first, 0x01), pdata(rest, 0x03)])

      assert :ok = CEcho.echo("127.0.0.1:#{port}")
    end

    test "is reached through Dcmix.Network.echo/2" do
      port = start_scp(self(), associate_ac(0), [echo_rsp(0x0000)])

      assert :ok = Network.echo("127.0.0.1:#{port}")
    end

    test "returns the status when the SCP answers with anything but success" do
      port = start_scp(self(), associate_ac(0), [echo_rsp(0xC000)])

      assert {:error, {:cecho_failed, 0xC000}} = CEcho.echo("127.0.0.1:#{port}")
      assert_receive :released
    end

    test "returns an error when the SCP rejects the Verification context" do
      port = start_scp(self(), associate_ac(3), [])

      assert {:error, :no_accepted_presentation_context} = CEcho.echo("127.0.0.1:#{port}")
      assert_receive :released
    end

    test "returns an error when the SCP rejects the association" do
      port = start_scp(self(), <<0x03, 0x00, 4::32-big, 0, 1, 1, 3>>, [])

      assert {:error, {:association_rejected, 1, 3}} = CEcho.echo("127.0.0.1:#{port}")
    end

    test "returns an error when the SCP aborts instead of answering" do
      port = start_scp(self(), associate_ac(0), [<<0x07, 0x00, 4::32-big, 0, 0, 2, 0>>])

      assert {:error, :association_aborted} = CEcho.echo("127.0.0.1:#{port}")
    end

    test "returns an error when the SCP asks to release instead of answering" do
      port = start_scp(self(), associate_ac(0), [<<0x05, 0x00, 4::32-big, 0::32>>])

      assert {:error, :unexpected_release} = CEcho.echo("127.0.0.1:#{port}")
    end

    test "returns an error when the answer isn't a C-ECHO-RSP to the request" do
      port = start_scp(self(), associate_ac(0), [echo_rsp(0x0000, 0x8020)])

      assert {:error, {:unexpected_response, %{command_field: 0x8020}}} =
               CEcho.echo("127.0.0.1:#{port}")
    end

    test "returns an error when the SCP doesn't answer in time" do
      port = start_scp(self(), associate_ac(0), [])

      assert {:error, {:recv_failed, :timeout}} =
               CEcho.echo("127.0.0.1:#{port}", timeout: 200)
    end

    test "returns an error when it can't connect" do
      assert {:error, {:connection_failed, _}} = CEcho.echo("127.0.0.1:1")
    end
  end

  # A one-shot SCP: answers the A-ASSOCIATE-RQ with `ac`, reports the request
  # and the C-ECHO command it receives to `parent`, sends `responses`, then
  # answers a release.
  defp start_scp(parent, ac, responses) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen, 5_000)
      {:ok, rq} = recv_pdu(socket)
      send(parent, {:associate_rq, rq})
      :ok = :gen_tcp.send(socket, ac)
      serve(socket, parent, ac, responses)
      :gen_tcp.close(listen)
    end)

    port
  end

  defp serve(socket, _parent, <<0x03, _::binary>>, _responses), do: :gen_tcp.close(socket)

  defp serve(socket, parent, _ac, responses) do
    case recv_pdu(socket) do
      {:ok, <<0x04, _::binary-size(5), _len::32, _ctx, _hdr, command::binary>>} ->
        send(parent, {:command, command})
        Enum.each(responses, &:gen_tcp.send(socket, &1))
        socket |> recv_pdu() |> answer_release(socket, parent)

      pdu ->
        answer_release(pdu, socket, parent)
    end
  end

  defp answer_release({:ok, <<0x05, _::binary>>}, socket, parent) do
    :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)
    send(parent, :released)
    :gen_tcp.close(socket)
  end

  defp answer_release(_closed_or_aborted, socket, _parent), do: :gen_tcp.close(socket)

  defp recv_pdu(socket) do
    with {:ok, <<_type, _reserved, length::32-big>> = header} <- :gen_tcp.recv(socket, 6, 5_000),
         {:ok, payload} <- :gen_tcp.recv(socket, length, 5_000) do
      {:ok, header <> payload}
    end
  end

  # An A-ASSOCIATE-AC for one presentation context (ID 1) with the given result
  defp associate_ac(result) do
    ts_item = <<0x40, 0x00, byte_size(@implicit_vr_le)::16-big, @implicit_vr_le::binary>>
    pc_content = <<1, 0x00, result, 0x00, ts_item::binary>>
    pc_item = <<0x21, 0x00, byte_size(pc_content)::16-big, pc_content::binary>>
    max_length = <<0x51, 0x00, 4::16-big, 65_536::32-big>>
    user_info = <<0x50, 0x00, byte_size(max_length)::16-big, max_length::binary>>

    payload =
      IO.iodata_to_binary([
        <<1::16-big, 0::16>>,
        String.pad_trailing("TEST_SCP", 16),
        String.pad_trailing("TEST_SCU", 16),
        <<0::256>>,
        pc_item,
        user_info
      ])

    <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>
  end

  # A C-ECHO-RSP (or, for a wrong-answer test, another command field) as a P-DATA PDU
  defp echo_rsp(status, command_field \\ 0x8030) do
    uid = @verification <> <<0>>

    elements =
      IO.iodata_to_binary([
        <<0x0000::16-little, 0x0002::16-little, byte_size(uid)::32-little, uid::binary>>,
        <<0x0000::16-little, 0x0100::16-little, 2::32-little, command_field::16-little>>,
        <<0x0000::16-little, 0x0120::16-little, 2::32-little, 1::16-little>>,
        <<0x0000::16-little, 0x0800::16-little, 2::32-little, 0x0101::16-little>>,
        <<0x0000::16-little, 0x0900::16-little, 2::32-little, status::16-little>>
      ])

    command =
      <<0x0000::16-little, 0x0000::16-little, 4::32-little, byte_size(elements)::32-little,
        elements::binary>>

    pdata(command, 0x03)
  end

  # A P-DATA PDU carrying one PDV on context 1 with the given control header
  defp pdata(data, control_header) do
    pdv = <<byte_size(data) + 2::32-big, 1, control_header, data::binary>>
    <<0x04, 0x00, byte_size(pdv)::32-big, pdv::binary>>
  end
end
