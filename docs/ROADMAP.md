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

## Planned Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Pixel Data Decompression** | Decode JPEG, JPEG2000, RLE compressed images | High |
| **Transfer Syntax Conversion** | Transcode between transfer syntaxes | High |
| **DICOM Networking (DIMSE)** | C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET | High |
| **Storage SCP/SCU** | Send/receive DICOM files over network | High |
| **Query/Retrieve** | Find and retrieve studies from PACS | Medium |
| **DICOMDIR** | Create/read media directory files | Medium |
| **Anonymization** | De-identify patient data | Medium |
| **Validation** | IOD conformance checking | Low |
| **Structured Reports** | SR document support | Low |
| **Presentation States** | GSPS support | Low |

## Feature Comparison

| Capability | dcmix | dicom-rs | dcmtk |
|------------|-------|----------|-------|
| File I/O | Yes | Yes | Yes |
| Transfer Syntaxes | Yes | Yes | Yes |
| JSON/XML Export | Yes | Yes | Yes |
| Pixel Decompression | No | Yes | Yes |
| DICOM Networking | No | Yes | Yes |
| Image Export | Yes | Yes | Yes |
| DICOMDIR | No | No | Yes |
| Anonymization | No | No | Yes |
