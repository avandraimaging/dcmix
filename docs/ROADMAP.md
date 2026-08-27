# Dcmix Roadmap

Dcmix aims to bring comprehensive DICOM support to Elixir, inspired by [dcmtk](https://dicom.offis.de/dcmtk.php.en) (C++) and [dicom-rs](https://github.com/Enet4/dicom-rs) (Rust).

## Implemented Features

| Feature | Description | Status |
|---------|-------------|--------|
| **File Parsing** | Read DICOM Part 10 files | Complete |
| **File Writing** | Write DICOM files with meta information | Complete |
| **Transfer Syntaxes** | Implicit VR LE, Explicit VR LE/BE | Complete |
| **Encapsulated Pixel Data** | Store/retrieve compressed pixel data as fragments | Complete |
| **JSON Export** | DICOM JSON Model (PS3.18 F.2) | Complete |
| **XML Export** | Native DICOM Model (PS3.19) | Complete |
| **Text Dump** | Human-readable output (dcmdump style) | Complete |
| **Private Tags** | Read/write vendor private data elements | Complete |
| **Data Dictionary** | Standard DICOM tags and VRs | Complete |
| **CLI Tools** | `dcmix.dump`, `dcmix.to_json`, `dcmix.to_xml`, `dcmix.to_image` | Complete |
| **Image Export** | Export pixel data to PNG, PPM, PGM image files | Complete |
| **Multi-frame Export** | Export all frames to separate image files | Complete |
| **JSON Import** | Create DICOM from JSON | Complete |
| **XML Import** | Create DICOM from XML | Complete |
| **Image Import** | Import pixel data from image files | Complete |
| **Multi-frame Import** | Create multi-frame DICOM from multiple images | Complete |
| **DICOM Networking (C-FIND SCU)** | Query remote PACS servers via C-FIND | Complete |
| **DICOM Networking (C-STORE SCU)** | Send DICOM instances to a remote SCP via C-STORE | Complete |

## Planned Features

`Status` reflects current code state: `Not started` means no implementation
exists yet; `Partial` means some sub-operations are complete (see the row
description for what is and isn't done). C-FIND SCU and C-STORE SCU are
shipped — see the Implemented Features table above.

| Feature | Description | Status | Priority |
|---------|-------------|--------|----------|
| **Pixel Data Decompression** | Decode JPEG, JPEG2000, RLE compressed images | Not started | High |
| **Transfer Syntax Conversion** | Transcode between transfer syntaxes | Not started | High |
| **C-ECHO** | DIMSE association verification (SCU + SCP) | Not started | High |
| **C-STORE** | Send and receive DICOM files over the network | Partial — SCU done | High |
| **C-MOVE** | Retrieve studies from PACS to a destination AE | Not started | Medium |
| **C-GET** | Retrieve studies over the active association | Not started | Medium |
| **DICOMDIR** | Create/read media directory files | Not started | Medium |
| **Anonymization** | De-identify patient data | Not started | Medium |
| **Validation** | IOD conformance checking | Not started | Low |
| **Structured Reports** | SR document support | Not started | Low |
| **Presentation States** | GSPS support | Not started | Low |

## Feature Comparison

| Capability | dcmix | dicom-rs | dcmtk |
|------------|-------|----------|-------|
| File I/O | Yes | Yes | Yes |
| Transfer Syntaxes | Yes | Yes | Yes |
| JSON/XML Export | Yes | Yes | Yes |
| Pixel Decompression | No | Yes | Yes |
| DICOM Networking | Partial | Yes | Yes |
| Image Export | Yes | Yes | Yes |
| DICOMDIR | No | No | Yes |
| Anonymization | No | No | Yes |
