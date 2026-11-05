defmodule Dcmix.Network.StorageSOPClasses do
  @moduledoc """
  Storage SOP Classes, with their PS3.6 keywords: those proposed by
  default when acting as a Storage SCP inside an SCU association (C-GET
  sub-operations), and those a listener's Storage SCP
  (`Dcmix.Network.Listener`) accepts by default, which add every SR Storage
  SOP Class.

  The classes proposed are dcmtk's `dcmLongSCUStorageSOPClassUIDs`
  (`dcmdata/libsrc/dcuid.cc`), in its order, the list getscu and movescu
  propose; entries dcmtk comments out are omitted here too.
  """

  @classes [
    {"AmbulatoryECGWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.1.3"},
    {"ArterialPulseWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.5.1"},
    {"AutorefractionMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.2"},
    {"BasicStructuredDisplayStorage", "1.2.840.10008.5.1.4.1.1.131"},
    {"BasicTextSRStorage", "1.2.840.10008.5.1.4.1.1.88.11"},
    {"BasicVoiceAudioWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.4.1"},
    {"BlendingSoftcopyPresentationStateStorage", "1.2.840.10008.5.1.4.1.1.11.4"},
    {"BreastTomosynthesisImageStorage", "1.2.840.10008.5.1.4.1.1.13.1.3"},
    {"CardiacElectrophysiologyWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.3.1"},
    {"ChestCADSRStorage", "1.2.840.10008.5.1.4.1.1.88.65"},
    {"ColonCADSRStorage", "1.2.840.10008.5.1.4.1.1.88.69"},
    {"ColorSoftcopyPresentationStateStorage", "1.2.840.10008.5.1.4.1.1.11.2"},
    {"Comprehensive3DSRStorage", "1.2.840.10008.5.1.4.1.1.88.34"},
    {"ComprehensiveSRStorage", "1.2.840.10008.5.1.4.1.1.88.33"},
    {"ComputedRadiographyImageStorage", "1.2.840.10008.5.1.4.1.1.1"},
    {"CTImageStorage", "1.2.840.10008.5.1.4.1.1.2"},
    {"DeformableSpatialRegistrationStorage", "1.2.840.10008.5.1.4.1.1.66.3"},
    {"DigitalIntraOralXRayImageStorageForPresentation", "1.2.840.10008.5.1.4.1.1.1.3"},
    {"DigitalIntraOralXRayImageStorageForProcessing", "1.2.840.10008.5.1.4.1.1.1.3.1"},
    {"DigitalMammographyXRayImageStorageForPresentation", "1.2.840.10008.5.1.4.1.1.1.2"},
    {"DigitalMammographyXRayImageStorageForProcessing", "1.2.840.10008.5.1.4.1.1.1.2.1"},
    {"DigitalXRayImageStorageForPresentation", "1.2.840.10008.5.1.4.1.1.1.1"},
    {"DigitalXRayImageStorageForProcessing", "1.2.840.10008.5.1.4.1.1.1.1.1"},
    {"EncapsulatedCDAStorage", "1.2.840.10008.5.1.4.1.1.104.2"},
    {"EncapsulatedPDFStorage", "1.2.840.10008.5.1.4.1.1.104.1"},
    {"EnhancedCTImageStorage", "1.2.840.10008.5.1.4.1.1.2.1"},
    {"EnhancedMRColorImageStorage", "1.2.840.10008.5.1.4.1.1.4.3"},
    {"EnhancedMRImageStorage", "1.2.840.10008.5.1.4.1.1.4.1"},
    {"EnhancedPETImageStorage", "1.2.840.10008.5.1.4.1.1.130"},
    {"EnhancedSRStorage", "1.2.840.10008.5.1.4.1.1.88.22"},
    {"EnhancedUSVolumeStorage", "1.2.840.10008.5.1.4.1.1.6.2"},
    {"EnhancedXAImageStorage", "1.2.840.10008.5.1.4.1.1.12.1.1"},
    {"EnhancedXRFImageStorage", "1.2.840.10008.5.1.4.1.1.12.2.1"},
    {"GeneralAudioWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.4.2"},
    {"GeneralECGWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.1.2"},
    {"GrayscaleSoftcopyPresentationStateStorage", "1.2.840.10008.5.1.4.1.1.11.1"},
    {"HemodynamicWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.2.1"},
    {"ImplantationPlanSRStorage", "1.2.840.10008.5.1.4.1.1.88.70"},
    {"IntraocularLensCalculationsStorage", "1.2.840.10008.5.1.4.1.1.78.8"},
    {"IntravascularOpticalCoherenceTomographyImageStorageForPresentation",
     "1.2.840.10008.5.1.4.1.1.14.1"},
    {"IntravascularOpticalCoherenceTomographyImageStorageForProcessing",
     "1.2.840.10008.5.1.4.1.1.14.2"},
    {"KeratometryMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.3"},
    {"KeyObjectSelectionDocumentStorage", "1.2.840.10008.5.1.4.1.1.88.59"},
    {"LegacyConvertedEnhancedCTImageStorage", "1.2.840.10008.5.1.4.1.1.2.2"},
    {"LegacyConvertedEnhancedMRImageStorage", "1.2.840.10008.5.1.4.1.1.4.4"},
    {"LegacyConvertedEnhancedPETImageStorage", "1.2.840.10008.5.1.4.1.1.128.1"},
    {"LensometryMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.1"},
    {"MacularGridThicknessAndVolumeReportStorage", "1.2.840.10008.5.1.4.1.1.79.1"},
    {"MammographyCADSRStorage", "1.2.840.10008.5.1.4.1.1.88.50"},
    {"MRImageStorage", "1.2.840.10008.5.1.4.1.1.4"},
    {"MRSpectroscopyStorage", "1.2.840.10008.5.1.4.1.1.4.2"},
    {"MultiFrameGrayscaleByteSecondaryCaptureImageStorage", "1.2.840.10008.5.1.4.1.1.7.2"},
    {"MultiFrameGrayscaleWordSecondaryCaptureImageStorage", "1.2.840.10008.5.1.4.1.1.7.3"},
    {"MultiFrameSingleBitSecondaryCaptureImageStorage", "1.2.840.10008.5.1.4.1.1.7.1"},
    {"MultiFrameTrueColorSecondaryCaptureImageStorage", "1.2.840.10008.5.1.4.1.1.7.4"},
    {"NuclearMedicineImageStorage", "1.2.840.10008.5.1.4.1.1.20"},
    {"OphthalmicAxialMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.7"},
    {"OphthalmicPhotography16BitImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.5.2"},
    {"OphthalmicPhotography8BitImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.5.1"},
    {"OphthalmicThicknessMapStorage", "1.2.840.10008.5.1.4.1.1.81.1"},
    {"OphthalmicTomographyImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.5.4"},
    {"OphthalmicVisualFieldStaticPerimetryMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.80.1"},
    {"PositronEmissionTomographyImageStorage", "1.2.840.10008.5.1.4.1.1.128"},
    {"ProcedureLogStorage", "1.2.840.10008.5.1.4.1.1.88.40"},
    {"PseudoColorSoftcopyPresentationStateStorage", "1.2.840.10008.5.1.4.1.1.11.3"},
    {"RawDataStorage", "1.2.840.10008.5.1.4.1.1.66"},
    {"RealWorldValueMappingStorage", "1.2.840.10008.5.1.4.1.1.67"},
    {"RespiratoryWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.6.1"},
    {"RTBeamsDeliveryInstructionStorage", "1.2.840.10008.5.1.4.34.7"},
    {"RTBeamsTreatmentRecordStorage", "1.2.840.10008.5.1.4.1.1.481.4"},
    {"RTBrachyTreatmentRecordStorage", "1.2.840.10008.5.1.4.1.1.481.6"},
    {"RTDoseStorage", "1.2.840.10008.5.1.4.1.1.481.2"},
    {"RTImageStorage", "1.2.840.10008.5.1.4.1.1.481.1"},
    {"RTIonBeamsTreatmentRecordStorage", "1.2.840.10008.5.1.4.1.1.481.9"},
    {"RTIonPlanStorage", "1.2.840.10008.5.1.4.1.1.481.8"},
    {"RTPlanStorage", "1.2.840.10008.5.1.4.1.1.481.5"},
    {"RTStructureSetStorage", "1.2.840.10008.5.1.4.1.1.481.3"},
    {"RTTreatmentSummaryRecordStorage", "1.2.840.10008.5.1.4.1.1.481.7"},
    {"SecondaryCaptureImageStorage", "1.2.840.10008.5.1.4.1.1.7"},
    {"SegmentationStorage", "1.2.840.10008.5.1.4.1.1.66.4"},
    {"SpatialFiducialsStorage", "1.2.840.10008.5.1.4.1.1.66.2"},
    {"SpatialRegistrationStorage", "1.2.840.10008.5.1.4.1.1.66.1"},
    {"SpectaclePrescriptionReportStorage", "1.2.840.10008.5.1.4.1.1.78.6"},
    {"StereometricRelationshipStorage", "1.2.840.10008.5.1.4.1.1.77.1.5.3"},
    {"SubjectiveRefractionMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.4"},
    {"SurfaceScanMeshStorage", "1.2.840.10008.5.1.4.1.1.68.1"},
    {"SurfaceScanPointCloudStorage", "1.2.840.10008.5.1.4.1.1.68.2"},
    {"SurfaceSegmentationStorage", "1.2.840.10008.5.1.4.1.1.66.5"},
    {"TwelveLeadECGWaveformStorage", "1.2.840.10008.5.1.4.1.1.9.1.1"},
    {"UltrasoundImageStorage", "1.2.840.10008.5.1.4.1.1.6.1"},
    {"UltrasoundMultiFrameImageStorage", "1.2.840.10008.5.1.4.1.1.3.1"},
    {"VideoEndoscopicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.1.1"},
    {"VideoMicroscopicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.2.1"},
    {"VideoPhotographicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.4.1"},
    {"VisualAcuityMeasurementsStorage", "1.2.840.10008.5.1.4.1.1.78.5"},
    {"VLEndoscopicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.1"},
    {"VLMicroscopicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.2"},
    {"VLPhotographicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.4"},
    {"VLSlideCoordinatesMicroscopicImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.3"},
    {"VLWholeSlideMicroscopyImageStorage", "1.2.840.10008.5.1.4.1.1.77.1.6"},
    {"XAXRFGrayscaleSoftcopyPresentationStateStorage", "1.2.840.10008.5.1.4.1.1.11.5"},
    {"XRay3DAngiographicImageStorage", "1.2.840.10008.5.1.4.1.1.13.1.1"},
    {"XRay3DCraniofacialImageStorage", "1.2.840.10008.5.1.4.1.1.13.1.2"},
    {"XRayAngiographicImageStorage", "1.2.840.10008.5.1.4.1.1.12.1"},
    {"XRayRadiationDoseSRStorage", "1.2.840.10008.5.1.4.1.1.88.67"},
    {"XRayRadiofluoroscopicImageStorage", "1.2.840.10008.5.1.4.1.1.12.2"},
    {"HardcopyColorImageStorage", "1.2.840.10008.5.1.1.30"},
    {"HardcopyGrayscaleImageStorage", "1.2.840.10008.5.1.1.29"},
    {"NuclearMedicineImageStorageRetired", "1.2.840.10008.5.1.4.1.1.5"},
    {"StandaloneCurveStorage", "1.2.840.10008.5.1.4.1.1.9"},
    {"StandaloneModalityLUTStorage", "1.2.840.10008.5.1.4.1.1.10"},
    {"StandaloneOverlayStorage", "1.2.840.10008.5.1.4.1.1.8"},
    {"StandalonePETCurveStorage", "1.2.840.10008.5.1.4.1.1.129"},
    {"StandaloneVOILUTStorage", "1.2.840.10008.5.1.4.1.1.11"},
    {"StoredPrintStorage", "1.2.840.10008.5.1.1.27"},
    {"UltrasoundImageStorageRetired", "1.2.840.10008.5.1.4.1.1.6"},
    {"UltrasoundMultiFrameImageStorageRetired", "1.2.840.10008.5.1.4.1.1.3"},
    {"VLImageStorageTrial", "1.2.840.10008.5.1.4.1.1.77.1"},
    {"VLMultiFrameImageStorageTrial", "1.2.840.10008.5.1.4.1.1.77.2"},
    {"XRayAngiographicBiPlaneImageStorage", "1.2.840.10008.5.1.4.1.1.12.3"}
  ]

  # SR Storage SOP Classes left out of the 120
  @more_sr_classes [
    {"TextSRStorageTrial", "1.2.840.10008.5.1.4.1.1.88.1"},
    {"AudioSRStorageTrial", "1.2.840.10008.5.1.4.1.1.88.2"},
    {"DetailSRStorageTrial", "1.2.840.10008.5.1.4.1.1.88.3"},
    {"ComprehensiveSRStorageTrial", "1.2.840.10008.5.1.4.1.1.88.4"},
    {"ExtensibleSRStorage", "1.2.840.10008.5.1.4.1.1.88.35"},
    {"RadiopharmaceuticalRadiationDoseSRStorage", "1.2.840.10008.5.1.4.1.1.88.68"},
    {"AcquisitionContextSRStorage", "1.2.840.10008.5.1.4.1.1.88.71"},
    {"SimplifiedAdultEchoSRStorage", "1.2.840.10008.5.1.4.1.1.88.72"},
    {"PatientRadiationDoseSRStorage", "1.2.840.10008.5.1.4.1.1.88.73"},
    {"PlannedImagingAgentAdministrationSRStorage", "1.2.840.10008.5.1.4.1.1.88.74"},
    {"PerformedImagingAgentAdministrationSRStorage", "1.2.840.10008.5.1.4.1.1.88.75"},
    {"EnhancedXRayRadiationDoseSRStorage", "1.2.840.10008.5.1.4.1.1.88.76"},
    {"WaveformAnnotationSRStorage", "1.2.840.10008.5.1.4.1.1.88.77"}
  ]

  @uids Enum.map(@classes, &elem(&1, 1))
  @accepted_uids @uids ++ Enum.map(@more_sr_classes, &elem(&1, 1))
  @keyword_by_uid Map.new(@classes ++ @more_sr_classes, fn {keyword, uid} -> {uid, keyword} end)

  @doc """
  Returns the Storage SOP Class UIDs proposed for C-GET sub-operations (120
  entries, dcmtk order).

  A C-GET proposes one presentation context per Storage SOP Class, beside its
  Query/Retrieve context, and an association allows at most 128 presentation
  contexts. dcmtk caps the list at 120 to leave room for those.
  """
  @spec uids() :: [String.t()]
  def uids, do: @uids

  @doc """
  Returns the Storage SOP Class UIDs a Storage SCP accepts by default:
  `uids/0` and every SR Storage SOP Class.

  A Storage SCP only answers the presentation contexts it is offered, so the
  classes it accepts aren't bound by the 128-context limit that caps `uids/0`.
  """
  @spec accepted_uids() :: [String.t()]
  def accepted_uids, do: @accepted_uids

  @doc """
  Returns the Storage SOP Classes in `accepted_uids/0` as `{keyword, uid}`,
  keyword being the class's PS3.6 keyword. `Dcmix.Network.SOPClassUID` has a
  function for each, named for its keyword.
  """
  @spec classes() :: [{String.t(), String.t()}]
  def classes, do: @classes ++ @more_sr_classes

  @doc """
  Returns the PS3.6 keyword of a Storage SOP Class in `accepted_uids/0`, or
  nil.

  ## Examples

      iex> Dcmix.Network.StorageSOPClasses.keyword("1.2.840.10008.5.1.4.1.1.88.11")
      "BasicTextSRStorage"
  """
  @spec keyword(String.t()) :: String.t() | nil
  def keyword(uid), do: Map.get(@keyword_by_uid, uid)
end
