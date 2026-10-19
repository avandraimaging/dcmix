# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- DICOM networking with C-MOVE SCU support: `Dcmix.Network.move/3`
  (delegating to `Dcmix.Network.CMove.move/3`) asks the SCP to send the
  instances matching an identifier, at any Query/Retrieve Level, to
  `:destination_ae_title`, and returns a `Dcmix.Network.CMove.Result` with
  the final status, sub-operation counts and Failed SOP Instance UID List.
  Each C-MOVE-RSP is given to the `:on_response` callback, which can cancel
  the move. `:message_id`, `:priority` and both query models are supported.
- `Dcmix.Network.DataSetCodec` encodes and decodes a DIMSE message's data set
  in its context's transfer syntax; C-FIND and C-GET now use it.
- `Dcmix.Network.DIMSE.build_cmove_rq/4`; the C-MOVE command fields, the
  Q/R MOVE SOP Class UIDs, and the Move Destination Unknown and
  sub-operations-complete-with-failures statuses as constants.

- `Dcmix.Network.InstanceFile` writes an instance received over the network
  to a Part 10 file as it arrives, as C-GET's bit-preserving storage did; C-GET
  now uses it.
- A Storage SCP: given `:handler` (a `Dcmix.Network.SCP.Handler`) and
  `:storage_directory`, `Dcmix.Network.Listener` accepts the Storage SOP
  Classes, writes each instance sent with C-STORE to a file as it arrives,
  and calls the handler's `handle_store/2` with its path, UIDs, transfer
  syntax, calling AE title and Move Originator; the status it returns is sent
  in the C-STORE-RSP. `:storage_sop_classes` and `:storage_transfer_syntaxes`
  narrow what is accepted; compressed transfer syntaxes are taken as sent.
- `Dcmix.Network.DIMSE`: `build_cstore_rq/4`, and `decode_command/1` returns
  the Move Originator AE Title and Message ID.

### Changed

- `Dcmix.Network.Negotiation` accepts each presentation context with the
  requestor's most preferred transfer syntax among those supported, rather
  than ours.
- The optional `thousand_island` dependency, needed to run a listener, is
  now `~> 1.6`.
- `Dcmix.Network.get/3` defaults to the Study Root query model, as
  `Dcmix.Network.move/3` does, instead of Patient Root. Study Root needs only
  the Study, Series and SOP Instance UIDs to retrieve below the patient
  level, matches C-FIND's Study Root queries, and is the model PACS most
  commonly support. Pass `query_model: :patient_root` for the old behaviour.
- CI tests against Elixir 1.20 / OTP 29, and dcmix compiles there without
  warnings; Elixir `~> 1.18` is still supported.

## [0.3.0] - 2026-10-16

### Added

- DICOM networking with C-ECHO SCU support: `Dcmix.Network.echo/2` (delegating
  to `Dcmix.Network.CEcho.echo/2`) returns `:ok` when the node answers with
  success, or `{:error, {:cecho_failed, status}}` for any other status.
- `Dcmix.Network.DIMSE`: `build_cecho_rq/1`.
- A listener for DICOM associations, as an SCP: `Dcmix.Network.Listener` is a
  child spec for the caller's supervision tree that accepts associations on a
  port and answers C-ECHO. It rejects a called AE title other than its own,
  and an association beyond `:max_associations` as rejected-transient,
  local-limit-exceeded. `Dcmix.Network.SCP` serves each association, and
  `Dcmix.Network.Negotiation` decides how to answer each A-ASSOCIATE-RQ.
- An optional dependency on `thousand_island`, needed only to run a listener.
  Without it, `Dcmix.Network.Listener` raises, saying to add it.
- `Dcmix.Network.PDU`: decoding of A-ASSOCIATE-RQ, and `encode_associate_ac/3`,
  `encode_associate_rj/3` and `encode_release_rp/0`; `Dcmix.Network.DIMSE`:
  `build_cecho_rsp/2`.
- Network protocol constants in one place each: `Dcmix.Network.SOPClassUID`
  (Verification and Q/R FIND/GET UIDs), `Dcmix.Network.ApplicationContext`,
  and the pattern-safe macro modules `Dcmix.Network.DIMSE.CommandField`,
  `Dcmix.Network.DIMSE.Status`, `Dcmix.Network.PDU.Type`,
  `Dcmix.Network.PDU.PresentationContextResult` and
  `Dcmix.Network.PDU.AssociateRJ` (the A-ASSOCIATE-RJ results, sources and
  reasons, each reason prefixed with its source).
- `Dcmix.UID`: dcmix's root UID, Implementation Class UID and Implementation
  Version Name, and `generate/0`.
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
  64 KiB (an A-ASSOCIATE-RQ or -AC at 1 MiB).
- A stall after a PDU header has been read is reported as
  `{:error, :pdu_read_timeout}` (C-FIND aborts the association;
  C-GET returns it as a timeout), instead of being read as a fresh PDU.
- dcmix identifies itself with one Implementation Class UID,
  `1.2.826.0.1.3680043.10.1712.1`, in association requests and written files'
  meta header, instead of two unregistered ones. The Implementation Version
  Name is `DCMIX_` plus the library version in both places (was `DCMIX_010`
  and `DCMIX_001`). Both are in the new `Dcmix.UID`.
- `Dcmix.Writer.generate_uid/0` generates UIDs under
  `1.2.826.0.1.3680043.10.1712.1.1`, and the time component no longer has
  leading zeros, which made UIDs generated before 10:00 UTC invalid.

### Fixed

- An A-ASSOCIATE-RJ's result is read from its own byte. It was read from the
  source byte, so a transient local-limit rejection came back as
  `{:association_rejected, 3, 2}` rather than `{:association_rejected, 2, 2}`.
  The decoded PDU also carries the source.

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

[Unreleased]: https://github.com/avandraimaging/dcmix/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/avandraimaging/dcmix/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/avandraimaging/dcmix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/avandraimaging/dcmix/releases/tag/v0.1.0
