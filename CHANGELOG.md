# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/avandra/dcmix/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/avandra/dcmix/releases/tag/v0.1.0
