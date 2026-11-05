defmodule Dcmix.Network.ConstantsTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.{ApplicationContext, SOPClassUID, StorageSOPClasses}

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status
  require Dcmix.Network.PDU.AssociateRJ, as: AssociateRJ
  require Dcmix.Network.PDU.PresentationContextResult, as: ContextResult
  require Dcmix.Network.PDU.Type, as: PDUType

  test "Application Context Name matches PS3.7 A.2.1" do
    assert ApplicationContext.dicom() == "1.2.840.10008.3.1.1.1"
  end

  test "SOP Class UIDs match PS3.4" do
    assert SOPClassUID.verification() == "1.2.840.10008.1.1"
    assert SOPClassUID.patient_root_query_retrieve_move() == "1.2.840.10008.5.1.4.1.2.1.2"
    assert SOPClassUID.patient_root_query_retrieve_get() == "1.2.840.10008.5.1.4.1.2.1.3"
    assert SOPClassUID.study_root_query_retrieve_find() == "1.2.840.10008.5.1.4.1.2.2.1"
    assert SOPClassUID.study_root_query_retrieve_move() == "1.2.840.10008.5.1.4.1.2.2.2"
    assert SOPClassUID.study_root_query_retrieve_get() == "1.2.840.10008.5.1.4.1.2.2.3"
  end

  test "each Storage SOP Class has a function named for its PS3.6 keyword" do
    assert SOPClassUID.key_object_selection_document_storage() == "1.2.840.10008.5.1.4.1.1.88.59"
    assert SOPClassUID.basic_text_sr_storage() == "1.2.840.10008.5.1.4.1.1.88.11"
    assert SOPClassUID.ct_image_storage() == "1.2.840.10008.5.1.4.1.1.2"
    assert SOPClassUID.comprehensive_3d_sr_storage() == "1.2.840.10008.5.1.4.1.1.88.34"
    assert SOPClassUID.x_ray_3d_angiographic_image_storage() == "1.2.840.10008.5.1.4.1.1.13.1.1"

    assert SOPClassUID.ophthalmic_photography_16_bit_image_storage() ==
             "1.2.840.10008.5.1.4.1.1.77.1.5.2"

    assert SOPClassUID.chest_cad_sr_storage() == "1.2.840.10008.5.1.4.1.1.88.65"
    assert SOPClassUID.colon_cad_sr_storage() == "1.2.840.10008.5.1.4.1.1.88.69"
    assert SOPClassUID.mammography_cad_sr_storage() == "1.2.840.10008.5.1.4.1.1.88.50"
    assert SOPClassUID.standalone_voi_lut_storage() == "1.2.840.10008.5.1.4.1.1.11"

    assert SOPClassUID.xa_xrf_grayscale_softcopy_presentation_state_storage() ==
             "1.2.840.10008.5.1.4.1.1.11.5"

    for {_keyword, uid} <- StorageSOPClasses.classes() do
      assert Enum.count(SOPClassUID.__info__(:functions), fn {name, 0} ->
               apply(SOPClassUID, name, []) == uid
             end) == 1
    end
  end

  test "command fields match PS3.7 E.1" do
    assert CommandField.c_store_rq() == 0x0001
    assert CommandField.c_store_rsp() == 0x8001
    assert CommandField.c_get_rq() == 0x0010
    assert CommandField.c_get_rsp() == 0x8010
    assert CommandField.c_find_rq() == 0x0020
    assert CommandField.c_find_rsp() == 0x8020
    assert CommandField.c_move_rq() == 0x0021
    assert CommandField.c_move_rsp() == 0x8021
    assert CommandField.c_echo_rq() == 0x0030
    assert CommandField.c_echo_rsp() == 0x8030
    assert CommandField.c_cancel_rq() == 0x0FFF
  end

  test "statuses match PS3.4 / PS3.7 Annex C" do
    assert Status.success() == 0x0000
    assert Status.pending() == 0xFF00
    assert Status.pending_optional_keys_not_supported() == 0xFF01
    assert Status.cancel() == 0xFE00
    assert Status.sop_class_not_supported() == 0x0122
    assert Status.out_of_resources() == 0xA700
    assert Status.cannot_understand() == 0xC000
    assert Status.move_destination_unknown() == 0xA801
    assert Status.sub_operations_complete_with_failures() == 0xB000
  end

  test "PDU types match PS3.8 9.3" do
    assert PDUType.associate_rq() == 0x01
    assert PDUType.associate_ac() == 0x02
    assert PDUType.associate_rj() == 0x03
    assert PDUType.p_data_tf() == 0x04
    assert PDUType.release_rq() == 0x05
    assert PDUType.release_rp() == 0x06
    assert PDUType.abort() == 0x07
  end

  test "presentation context results match PS3.8 Table 9-18" do
    assert ContextResult.acceptance() == 0
    assert ContextResult.user_rejection() == 1
    assert ContextResult.no_reason() == 2
    assert ContextResult.abstract_syntax_not_supported() == 3
    assert ContextResult.transfer_syntaxes_not_supported() == 4
  end

  test "A-ASSOCIATE-RJ values match PS3.8 Table 9-21" do
    assert AssociateRJ.rejected_permanent() == 1
    assert AssociateRJ.rejected_transient() == 2

    assert AssociateRJ.source_service_user() == 1
    assert AssociateRJ.source_acse() == 2
    assert AssociateRJ.source_presentation() == 3

    assert AssociateRJ.service_user_no_reason_given() == 1
    assert AssociateRJ.service_user_application_context_name_not_supported() == 2
    assert AssociateRJ.service_user_calling_ae_title_not_recognized() == 3
    assert AssociateRJ.service_user_called_ae_title_not_recognized() == 7

    assert AssociateRJ.acse_no_reason_given() == 1
    assert AssociateRJ.acse_protocol_version_not_supported() == 2

    assert AssociateRJ.presentation_temporary_congestion() == 1
    assert AssociateRJ.presentation_local_limit_exceeded() == 2
  end

  test "constants work in patterns" do
    assert match?(%{command_field: CommandField.c_echo_rsp()}, %{command_field: 0x8030})
    assert match?(<<PDUType.p_data_tf(), _::binary>>, <<0x04, 0x00>>)

    assert match?(
             {:association_rejected, AssociateRJ.rejected_transient(), _},
             {:association_rejected, 2, 2}
           )
  end
end
