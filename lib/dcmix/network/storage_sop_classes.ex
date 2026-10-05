defmodule Dcmix.Network.StorageSOPClasses do
  @moduledoc """
  Storage SOP Class UIDs proposed by default when acting as a Storage SCP
  inside an SCU association (C-GET sub-operations).

  Ported from dcmtk's `dcmLongSCUStorageSOPClassUIDs`
  (`dcmdata/libsrc/dcuid.cc`), the list getscu and movescu propose with one
  presentation context per class. dcmtk caps it at 120 entries so the
  Q/R contexts still fit within the 128 presentation contexts an
  association allows; entries dcmtk comments out are omitted here too.
  """

  @uids [
    # AmbulatoryECGWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.1.3",
    # ArterialPulseWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.5.1",
    # AutorefractionMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.2",
    # BasicStructuredDisplayStorage
    "1.2.840.10008.5.1.4.1.1.131",
    # BasicTextSRStorage
    "1.2.840.10008.5.1.4.1.1.88.11",
    # BasicVoiceAudioWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.4.1",
    # BlendingSoftcopyPresentationStateStorage
    "1.2.840.10008.5.1.4.1.1.11.4",
    # BreastTomosynthesisImageStorage
    "1.2.840.10008.5.1.4.1.1.13.1.3",
    # CardiacElectrophysiologyWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.3.1",
    # ChestCADSRStorage
    "1.2.840.10008.5.1.4.1.1.88.65",
    # ColonCADSRStorage
    "1.2.840.10008.5.1.4.1.1.88.69",
    # ColorSoftcopyPresentationStateStorage
    "1.2.840.10008.5.1.4.1.1.11.2",
    # Comprehensive3DSRStorage
    "1.2.840.10008.5.1.4.1.1.88.34",
    # ComprehensiveSRStorage
    "1.2.840.10008.5.1.4.1.1.88.33",
    # ComputedRadiographyImageStorage
    "1.2.840.10008.5.1.4.1.1.1",
    # CTImageStorage
    "1.2.840.10008.5.1.4.1.1.2",
    # DeformableSpatialRegistrationStorage
    "1.2.840.10008.5.1.4.1.1.66.3",
    # DigitalIntraOralXRayImageStorageForPresentation
    "1.2.840.10008.5.1.4.1.1.1.3",
    # DigitalIntraOralXRayImageStorageForProcessing
    "1.2.840.10008.5.1.4.1.1.1.3.1",
    # DigitalMammographyXRayImageStorageForPresentation
    "1.2.840.10008.5.1.4.1.1.1.2",
    # DigitalMammographyXRayImageStorageForProcessing
    "1.2.840.10008.5.1.4.1.1.1.2.1",
    # DigitalXRayImageStorageForPresentation
    "1.2.840.10008.5.1.4.1.1.1.1",
    # DigitalXRayImageStorageForProcessing
    "1.2.840.10008.5.1.4.1.1.1.1.1",
    # EncapsulatedCDAStorage
    "1.2.840.10008.5.1.4.1.1.104.2",
    # EncapsulatedPDFStorage
    "1.2.840.10008.5.1.4.1.1.104.1",
    # EnhancedCTImageStorage
    "1.2.840.10008.5.1.4.1.1.2.1",
    # EnhancedMRColorImageStorage
    "1.2.840.10008.5.1.4.1.1.4.3",
    # EnhancedMRImageStorage
    "1.2.840.10008.5.1.4.1.1.4.1",
    # EnhancedPETImageStorage
    "1.2.840.10008.5.1.4.1.1.130",
    # EnhancedSRStorage
    "1.2.840.10008.5.1.4.1.1.88.22",
    # EnhancedUSVolumeStorage
    "1.2.840.10008.5.1.4.1.1.6.2",
    # EnhancedXAImageStorage
    "1.2.840.10008.5.1.4.1.1.12.1.1",
    # EnhancedXRFImageStorage
    "1.2.840.10008.5.1.4.1.1.12.2.1",
    # GeneralAudioWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.4.2",
    # GeneralECGWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.1.2",
    # GrayscaleSoftcopyPresentationStateStorage
    "1.2.840.10008.5.1.4.1.1.11.1",
    # HemodynamicWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.2.1",
    # ImplantationPlanSRStorage
    "1.2.840.10008.5.1.4.1.1.88.70",
    # IntraocularLensCalculationsStorage
    "1.2.840.10008.5.1.4.1.1.78.8",
    # IntravascularOpticalCoherenceTomographyImageStorageForPresentation
    "1.2.840.10008.5.1.4.1.1.14.1",
    # IntravascularOpticalCoherenceTomographyImageStorageForProcessing
    "1.2.840.10008.5.1.4.1.1.14.2",
    # KeratometryMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.3",
    # KeyObjectSelectionDocumentStorage
    "1.2.840.10008.5.1.4.1.1.88.59",
    # LegacyConvertedEnhancedCTImageStorage
    "1.2.840.10008.5.1.4.1.1.2.2",
    # LegacyConvertedEnhancedMRImageStorage
    "1.2.840.10008.5.1.4.1.1.4.4",
    # LegacyConvertedEnhancedPETImageStorage
    "1.2.840.10008.5.1.4.1.1.128.1",
    # LensometryMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.1",
    # MacularGridThicknessAndVolumeReportStorage
    "1.2.840.10008.5.1.4.1.1.79.1",
    # MammographyCADSRStorage
    "1.2.840.10008.5.1.4.1.1.88.50",
    # MRImageStorage
    "1.2.840.10008.5.1.4.1.1.4",
    # MRSpectroscopyStorage
    "1.2.840.10008.5.1.4.1.1.4.2",
    # MultiframeGrayscaleByteSecondaryCaptureImageStorage
    "1.2.840.10008.5.1.4.1.1.7.2",
    # MultiframeGrayscaleWordSecondaryCaptureImageStorage
    "1.2.840.10008.5.1.4.1.1.7.3",
    # MultiframeSingleBitSecondaryCaptureImageStorage
    "1.2.840.10008.5.1.4.1.1.7.1",
    # MultiframeTrueColorSecondaryCaptureImageStorage
    "1.2.840.10008.5.1.4.1.1.7.4",
    # NuclearMedicineImageStorage
    "1.2.840.10008.5.1.4.1.1.20",
    # OphthalmicAxialMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.7",
    # OphthalmicPhotography16BitImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.5.2",
    # OphthalmicPhotography8BitImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.5.1",
    # OphthalmicThicknessMapStorage
    "1.2.840.10008.5.1.4.1.1.81.1",
    # OphthalmicTomographyImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.5.4",
    # OphthalmicVisualFieldStaticPerimetryMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.80.1",
    # PositronEmissionTomographyImageStorage
    "1.2.840.10008.5.1.4.1.1.128",
    # ProcedureLogStorage
    "1.2.840.10008.5.1.4.1.1.88.40",
    # PseudoColorSoftcopyPresentationStateStorage
    "1.2.840.10008.5.1.4.1.1.11.3",
    # RawDataStorage
    "1.2.840.10008.5.1.4.1.1.66",
    # RealWorldValueMappingStorage
    "1.2.840.10008.5.1.4.1.1.67",
    # RespiratoryWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.6.1",
    # RTBeamsDeliveryInstructionStorage
    "1.2.840.10008.5.1.4.34.7",
    # RTBeamsTreatmentRecordStorage
    "1.2.840.10008.5.1.4.1.1.481.4",
    # RTBrachyTreatmentRecordStorage
    "1.2.840.10008.5.1.4.1.1.481.6",
    # RTDoseStorage
    "1.2.840.10008.5.1.4.1.1.481.2",
    # RTImageStorage
    "1.2.840.10008.5.1.4.1.1.481.1",
    # RTIonBeamsTreatmentRecordStorage
    "1.2.840.10008.5.1.4.1.1.481.9",
    # RTIonPlanStorage
    "1.2.840.10008.5.1.4.1.1.481.8",
    # RTPlanStorage
    "1.2.840.10008.5.1.4.1.1.481.5",
    # RTStructureSetStorage
    "1.2.840.10008.5.1.4.1.1.481.3",
    # RTTreatmentSummaryRecordStorage
    "1.2.840.10008.5.1.4.1.1.481.7",
    # SecondaryCaptureImageStorage
    "1.2.840.10008.5.1.4.1.1.7",
    # SegmentationStorage
    "1.2.840.10008.5.1.4.1.1.66.4",
    # SpatialFiducialsStorage
    "1.2.840.10008.5.1.4.1.1.66.2",
    # SpatialRegistrationStorage
    "1.2.840.10008.5.1.4.1.1.66.1",
    # SpectaclePrescriptionReportStorage
    "1.2.840.10008.5.1.4.1.1.78.6",
    # StereometricRelationshipStorage
    "1.2.840.10008.5.1.4.1.1.77.1.5.3",
    # SubjectiveRefractionMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.4",
    # SurfaceScanMeshStorage
    "1.2.840.10008.5.1.4.1.1.68.1",
    # SurfaceScanPointCloudStorage
    "1.2.840.10008.5.1.4.1.1.68.2",
    # SurfaceSegmentationStorage
    "1.2.840.10008.5.1.4.1.1.66.5",
    # TwelveLeadECGWaveformStorage
    "1.2.840.10008.5.1.4.1.1.9.1.1",
    # UltrasoundImageStorage
    "1.2.840.10008.5.1.4.1.1.6.1",
    # UltrasoundMultiframeImageStorage
    "1.2.840.10008.5.1.4.1.1.3.1",
    # VideoEndoscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.1.1",
    # VideoMicroscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.2.1",
    # VideoPhotographicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.4.1",
    # VisualAcuityMeasurementsStorage
    "1.2.840.10008.5.1.4.1.1.78.5",
    # VLEndoscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.1",
    # VLMicroscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.2",
    # VLPhotographicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.4",
    # VLSlideCoordinatesMicroscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.3",
    # VLWholeSlideMicroscopyImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1.6",
    # XAXRFGrayscaleSoftcopyPresentationStateStorage
    "1.2.840.10008.5.1.4.1.1.11.5",
    # XRay3DAngiographicImageStorage
    "1.2.840.10008.5.1.4.1.1.13.1.1",
    # XRay3DCraniofacialImageStorage
    "1.2.840.10008.5.1.4.1.1.13.1.2",
    # XRayAngiographicImageStorage
    "1.2.840.10008.5.1.4.1.1.12.1",
    # XRayRadiationDoseSRStorage
    "1.2.840.10008.5.1.4.1.1.88.67",
    # XRayRadiofluoroscopicImageStorage
    "1.2.840.10008.5.1.4.1.1.12.2",
    # RETIRED_HardcopyColorImageStorage
    "1.2.840.10008.5.1.1.30",
    # RETIRED_HardcopyGrayscaleImageStorage
    "1.2.840.10008.5.1.1.29",
    # RETIRED_NuclearMedicineImageStorage
    "1.2.840.10008.5.1.4.1.1.5",
    # RETIRED_StandaloneCurveStorage
    "1.2.840.10008.5.1.4.1.1.9",
    # RETIRED_StandaloneModalityLUTStorage
    "1.2.840.10008.5.1.4.1.1.10",
    # RETIRED_StandaloneOverlayStorage
    "1.2.840.10008.5.1.4.1.1.8",
    # RETIRED_StandalonePETCurveStorage
    "1.2.840.10008.5.1.4.1.1.129",
    # RETIRED_StandaloneVOILUTStorage
    "1.2.840.10008.5.1.4.1.1.11",
    # RETIRED_StoredPrintStorage
    "1.2.840.10008.5.1.1.27",
    # RETIRED_UltrasoundImageStorage
    "1.2.840.10008.5.1.4.1.1.6",
    # RETIRED_UltrasoundMultiframeImageStorage
    "1.2.840.10008.5.1.4.1.1.3",
    # RETIRED_VLImageStorage
    "1.2.840.10008.5.1.4.1.1.77.1",
    # RETIRED_VLMultiframeImageStorage
    "1.2.840.10008.5.1.4.1.1.77.2",
    # RETIRED_XRayAngiographicBiPlaneImageStorage
    "1.2.840.10008.5.1.4.1.1.12.3"
  ]

  @doc """
  Returns the default Storage SOP Class UIDs (120 entries, dcmtk order).
  """
  @spec uids() :: [String.t()]
  def uids, do: @uids
end
