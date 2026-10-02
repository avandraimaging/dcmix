# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- DICOM networking with C-GET SCU support: `Dcmix.Network.get/3` (delegating to
  `Dcmix.Network.CGet.get/3`) returns a `Dcmix.Network.CGet.Result`. Retrieved
  instances are streamed to Part 10 files as they arrive (bit-preserving), or
  discarded with `storage_mode: :ignore`.
- `Dcmix.Network.StorageSOPClasses`: the 120 Storage SOP Classes dcmtk proposes
  by default for C-GET sub-operations.
- `Dcmix.Network.Association`: `request/2` takes per-context proposals with
  SCP/SCU Role Selection (`:presentation_contexts`); accepted contexts carry
  their `:abstract_syntax` and the negotiated `:scu_role` / `:scp_role`;
  `accepted_context/2` finds the context for an abstract syntax; and
  `send_pdata/4` splits data larger than the peer's maximum PDU length.
- `Dcmix.Network.PDU`: encodes SCP/SCU Role Selection sub-items in an
  A-ASSOCIATE-RQ (`:role_selections`) and decodes them from an A-ASSOCIATE-AC.
- `Dcmix.Network.DIMSE`: `build_cget_rq/3`, `build_cstore_rsp/4`,
  `build_ccancel_rq/1`, `decode_command/1` and `dataset_present?/1`.
- `Dcmix.Writer.file_meta_header/4` encodes a Part 10 header for an already
  encoded data set.

### Changed

- Inbound P-DATA-TF PDUs longer than the proposed maximum PDU length are now
  refused with `{:error, :pdu_too_large}` for every network operation,
  including C-FIND, and the association is aborted. Other PDUs are capped at
  64 KiB (an A-ASSOCIATE-AC at 1 MiB).
- A stall after a PDU header has been read is reported as
  `{:error, :pdu_read_timeout}` (C-FIND aborts the association;
  C-GET returns it as a timeout), instead of being read as a fresh PDU.

## [0.2.0] - 2026-10-02

### Added

- `stop_before_pixels: true` option for `Dcmix.read_file/2` and `Dcmix.Parser.parse/2`:
  returns every element before the first top-level pixel data element, and reads
  the file only as far as that element, so a large image costs no more than its
  header. `:read_size` sets the first read (default 64 KiB), which doubles as needed.
- DICOM networking with C-FIND SCU support (`Dcmix.Network.query/3`), returning
  matches as DataSets.
- Multi-frame image export and import (`Dcmix.to_images/3`, `Dcmix.from_images/2`).

### Fixed

- Socket leak when no presentation context is accepted during association.
- Duplicate `decode_variable_items` base case in PDU decoding.

## [0.1.0] - 2025-01-27

### Added

- DICOM Part 10 file parsing with proper preamble and meta header handling
- File writing with automatic file meta information generation
- Transfer syntax support: Implicit VR Little Endian, Explicit VR Little/Big Endian
- Data dictionary with standard DICOM tags and VRs
- Export to JSON (DICOM JSON Model PS3.18 F.2)
- Export to XML (Native DICOM Model PS3.19)
- Human-readable dump output (dcmdump style)
- Private tag support for vendor data elements
- Pixel data export to PNG, PPM, and PGM formats
- Import from JSON, XML, and image files
- Mix tasks for CLI usage:
  - `mix dcmix.dump` - Display DICOM file contents
  - `mix dcmix.to_json` - Convert to JSON format
  - `mix dcmix.to_xml` - Convert to XML format
  - `mix dcmix.to_image` - Export pixel data to image
  - `mix dcmix.from_json` - Create DICOM from JSON
  - `mix dcmix.from_xml` - Create DICOM from XML
  - `mix dcmix.from_image` - Import pixel data from image

[Unreleased]: https://github.com/avandraimaging/dcmix/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/avandraimaging/dcmix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/avandraimaging/dcmix/releases/tag/v0.1.0
