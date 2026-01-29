# NEMA DICOM Test Fixture Attribution

The following test fixtures are from the **NEMA DICOM Sample Images** collection,
provided by the National Electrical Manufacturers Association (NEMA) for testing
DICOM implementations.

## Source

- **Provider**: NEMA (National Electrical Manufacturers Association)
- **Collection**: DICOM Multiframe MR Sample Images
- **URL**: ftp://medical.nema.org/medical/Dicom/Multiframe/MR/
- **Date Retrieved**: January 2026

## Files

| Filename | Original Name | Description | Dimensions |
|----------|---------------|-------------|------------|
| `nema_mr_spectroscopy_32x32.dcm` | OHSP1M1 | MR Spectroscopy metabolite map | 32x32x1 |
| `nema_mr_diffusion_128x128.dcm` | ONEDWEXP | MR Diffusion weighted image | 128x128x1 |
| `nema_mr_cardiac_256x256.dcm` | ONEHEART | MR Cardiac EPI short axis | 256x256x1 |
| `nema_mr_knee_multiframe_3.dcm` | LOCKNEE | MR Knee orthogonal localizers | 256x256x3 |
| `nema_mr_perfusion_multiframe_11.dcm` | MRVPWCBV | MR Perfusion cerebral blood volume | 128x128x11 |
| `nema_mr_brain_512x512.dcm` | ONEBRAIN | MR Brain axial STIR | 512x512x1 |
| `nema_mr_knee_512x512.dcm` | ONEKNEE | MR Knee sagittal T2W | 512x512x1 |

## Common Properties

All files share these characteristics:
- **Modality**: MR (Magnetic Resonance)
- **Transfer Syntax**: Explicit VR Little Endian (1.2.840.10008.1.2.1)
- **Bits Allocated**: 16
- **Photometric Interpretation**: MONOCHROME2
- **SOP Class**: Enhanced MR Image Storage (1.2.840.10008.5.1.4.1.1.4.1)

## License

These images are provided by NEMA for testing DICOM implementations and are
freely available for such purposes. The images use placeholder institution
names ("St. Nowhere Hospital") and manufacturer names ("Acme Medical Devices")
indicating they are synthetic test data without patient information.

---

## Replaced Files

The following files were previously used as test fixtures but have been replaced
due to uncertain provenance:

| Filename | Modality | Dimensions |
|----------|----------|------------|
| `0_ORIGINAL.dcm` | CR | 2140x1760 |
| `1_ORIGINAL.dcm` | DX | 2022x2022 |
| `2_ORIGINAL.dcm` | CT | 394x552 |

### Source

These files were found in Microsoft's Presidio project:
- **URL**: https://github.com/microsoft/presidio/tree/main/docs/samples/python/sample_data
- **License**: MIT (Presidio project license)

### Reason for Replacement

The Presidio repository does not document the original source or provenance of
these DICOM files. While the files themselves are distributed under MIT license
as part of Presidio, we cannot verify their ultimate origin or licensing terms.
To ensure clear provenance for testing, these files have been replaced with
official NEMA sample images which have well-documented origins.
