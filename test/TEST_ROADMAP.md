# Test Roadmap for Dcmix

This document outlines the current test coverage, identified gaps, and specific test scenarios that need to be implemented in future iterations.

## Current Test Coverage Summary

**As of January 2026:**
- **858 tests**, 0 failures
- **90.14% code coverage**
- **7 test fixtures** from NEMA (see `test/fixtures/NEMA_ATTRIBUTION.md`)

### What's Well Tested

| Area | Status | Notes |
|------|--------|-------|
| Uncompressed DICOM parsing | ✅ Complete | Implicit/Explicit VR Little Endian |
| Uncompressed DICOM writing | ✅ Complete | Explicit VR Little Endian |
| JSON export (PS3.18 F.2) | ✅ Complete | DICOM JSON Model |
| JSON import | ✅ Complete | With edge cases |
| XML export (PS3.19) | ✅ Complete | Native DICOM Model |
| XML import | ✅ Complete | With edge cases |
| Image export (PNG/PPM/PGM) | ✅ Complete | 8/16-bit grayscale, RGB |
| Image import (PNG/JPEG) | ✅ Complete | img2dcm equivalent |
| Multi-frame image export | ✅ Complete | Export all frames to separate files |
| Multi-frame image import | ✅ Complete | Create multi-frame from multiple images |
| Mix tasks | ✅ Complete | All 7 tasks tested |
| Value Representations | ✅ Complete | All 30 VRs defined |
| Person Names | ✅ Complete | Structured components |
| Sequences | ✅ Partial | Basic nesting |
| Private Tags | ✅ Partial | Basic support |

---

## Priority 1: Critical Gaps

### 1.1 Compressed Transfer Syntax Support

**Current State:** Transfer syntaxes are defined but compression is not implemented. Tests return errors for encapsulated pixel data.

#### Test Scenarios Needed

```
test/dcmix/parser/compressed_test.exs
```

**JPEG Baseline (1.2.840.10008.1.2.4.50):**
- [ ] Parse JPEG baseline compressed DICOM file
- [ ] Extract compressed pixel data fragments
- [ ] Decode JPEG to raw pixels (requires codec)
- [ ] Handle multi-fragment pixel data
- [ ] Verify image dimensions match header

**JPEG Lossless (1.2.840.10008.1.2.4.70):**
- [ ] Parse JPEG lossless compressed DICOM file
- [ ] Verify lossless round-trip (original == decoded)
- [ ] Handle 12-bit and 16-bit samples

**JPEG 2000 (1.2.840.10008.1.2.4.90, 1.2.840.10008.1.2.4.91):**
- [ ] Parse JPEG 2000 lossless compressed file
- [ ] Parse JPEG 2000 lossy compressed file
- [ ] Handle JP2 vs J2K codestream variants

**JPEG-LS (1.2.840.10008.1.2.4.80, 1.2.840.10008.1.2.4.81):**
- [ ] Parse JPEG-LS lossless compressed file
- [ ] Parse JPEG-LS near-lossless compressed file

**RLE Lossless (1.2.840.10008.1.2.5):**
- [ ] Parse RLE compressed DICOM file
- [ ] Decode RLE segments correctly
- [ ] Handle multi-frame RLE data
- [ ] Verify segment header parsing

**Deflated Transfer Syntax (1.2.840.10008.1.2.1.99):**
- [ ] Parse deflated explicit VR little endian file
- [ ] Decompress dataset correctly

#### Required Test Fixtures

```
test/fixtures/compressed/
├── jpeg_baseline_8bit.dcm
├── jpeg_baseline_12bit.dcm
├── jpeg_lossless.dcm
├── jpeg_lossless_sv1.dcm
├── jpeg2000_lossless.dcm
├── jpeg2000_lossy.dcm
├── jpegls_lossless.dcm
├── jpegls_nearlossy.dcm
├── rle_lossless.dcm
└── deflated.dcm
```

**Source for fixtures:** [dicom-test-files](https://github.com/robyoung/dicom-test-files) or generate using dcmtk's `dcmcjpeg`, `dcmcrle` tools.

---

### 1.2 Big Endian Transfer Syntax

**Current State:** Explicit VR Big Endian (1.2.840.10008.1.2.2) is defined but not tested.

#### Test Scenarios Needed

```
test/dcmix/parser/big_endian_test.exs
```

- [ ] Parse Explicit VR Big Endian DICOM file
- [ ] Verify 16-bit values are byte-swapped correctly
- [ ] Verify 32-bit values are byte-swapped correctly
- [ ] Verify floating point values (FL, FD) are correct
- [ ] Write Explicit VR Big Endian file
- [ ] Round-trip Big Endian file (read -> write -> read)

#### Required Test Fixtures

```
test/fixtures/
└── explicit_vr_big_endian.dcm
```

---

### 1.3 File Meta Information

**Current State:** File meta information is parsed but not comprehensively tested.

#### Test Scenarios Needed

```
test/dcmix/parser/file_meta_test.exs
```

**Parsing:**
- [ ] Verify 128-byte preamble handling
- [ ] Verify "DICM" magic number validation
- [ ] Parse FileMetaInformationGroupLength (0002,0000)
- [ ] Parse FileMetaInformationVersion (0002,0001)
- [ ] Parse MediaStorageSOPClassUID (0002,0002)
- [ ] Parse MediaStorageSOPInstanceUID (0002,0003)
- [ ] Parse TransferSyntaxUID (0002,0010)
- [ ] Parse ImplementationClassUID (0002,0012)
- [ ] Parse ImplementationVersionName (0002,0013)
- [ ] Handle optional SourceApplicationEntityTitle (0002,0016)
- [ ] Handle optional PrivateInformationCreatorUID (0002,0100)
- [ ] Handle optional PrivateInformation (0002,0102)

**Writing:**
- [ ] Generate correct File Meta Information header
- [ ] Calculate FileMetaInformationGroupLength correctly
- [ ] Always write File Meta as Explicit VR Little Endian
- [ ] Generate valid ImplementationClassUID
- [ ] Generate valid ImplementationVersionName

**Edge Cases:**
- [ ] Handle missing preamble (Part 10 violation, but seen in wild)
- [ ] Handle corrupted File Meta length
- [ ] Handle unknown File Meta elements

---

### 1.4 Multi-Frame Images

**Current State:** Multi-frame uncompressed images are well tested. Compressed multi-frame needs work.

#### Test Scenarios

```
test/dcmix/pixel_data/multi_frame_test.exs
test/dcmix/export/image_multiframe_test.exs
test/dcmix/import/image_multiframe_test.exs
```

- [x] Parse multi-frame uncompressed image
- [x] Extract specific frame by index
- [x] Extract all frames as list
- [x] Handle NumberOfFrames (0028,0008) attribute
- [x] Calculate frame size from image dimensions
- [ ] Parse multi-frame compressed image (encapsulated)
- [ ] Handle per-frame functional groups (enhanced IODs)
- [x] Export specific frame to PNG
- [x] Export all frames to PNG sequence
- [x] Import multiple images as multi-frame DICOM

#### Test Fixtures Available

```
test/fixtures/
├── nema_mr_knee_multiframe_3.dcm    (3 frames, 256x256)
├── nema_mr_perfusion_multiframe_11.dcm (11 frames, 128x128)
└── (compressed multi-frame fixtures still needed)
```

---

## Priority 2: Important Gaps

### 2.1 Deep Nested Sequences

**Current State:** Basic sequence nesting is tested, but deep nesting and edge cases are not.

#### Test Scenarios Needed

```
test/dcmix/data_set/sequence_test.exs (expand existing)
```

- [ ] Parse 5+ levels of nested sequences
- [ ] Handle empty sequence (no items)
- [ ] Handle sequence with empty items
- [ ] Handle undefined length sequences
- [ ] Handle undefined length items
- [ ] Verify sequence/item delimiters
- [ ] Write deeply nested sequences
- [ ] Round-trip nested sequences

---

### 2.2 Character Set Encoding

**Current State:** Only default character set (ISO-IR 6) is assumed.

#### Test Scenarios Needed

```
test/dcmix/charset_test.exs
```

**Specific Character Sets:**
- [ ] ISO-IR 100 (Latin-1)
- [ ] ISO-IR 101 (Latin-2)
- [ ] ISO-IR 144 (Cyrillic)
- [ ] ISO-IR 127 (Arabic)
- [ ] ISO-IR 126 (Greek)
- [ ] ISO-IR 138 (Hebrew)
- [ ] ISO-IR 148 (Latin-5/Turkish)
- [ ] ISO-IR 13 (Japanese Katakana)
- [ ] ISO-IR 166 (Thai)
- [ ] ISO 2022 IR 87 (Japanese Kanji)
- [ ] ISO 2022 IR 149 (Korean)
- [ ] ISO 2022 IR 58 (Simplified Chinese)
- [ ] ISO_IR 192 (UTF-8)
- [ ] GB18030 (Chinese)
- [ ] GBK (Chinese)

**Edge Cases:**
- [ ] Multi-valued SpecificCharacterSet
- [ ] Code extension with escape sequences
- [ ] Person names with different character sets per component

#### Required Test Fixtures

```
test/fixtures/charset/
├── latin1.dcm
├── utf8.dcm
├── japanese_kanji.dcm
├── korean.dcm
├── chinese_simplified.dcm
└── mixed_charset.dcm
```

---

### 2.3 Padding and Length Edge Cases

**Current State:** Basic padding is handled, edge cases are not tested.

#### Test Scenarios Needed

```
test/dcmix/data_element/padding_test.exs
```

- [ ] Odd-length string padding with space (0x20)
- [ ] Odd-length UI padding with null (0x00)
- [ ] Odd-length OB/OW padding with null
- [ ] Zero-length values
- [ ] Maximum length values (64KB for explicit VR short)
- [ ] Undefined length (0xFFFFFFFF) elements
- [ ] Explicit length vs undefined length handling

---

### 2.4 Additional Photometric Interpretations

**Current State:** MONOCHROME1, MONOCHROME2, RGB, YBR_FULL are tested.

#### Test Scenarios Needed

```
test/dcmix/export/image/photometric_test.exs
```

- [ ] PALETTE COLOR (requires LUT handling)
- [ ] YBR_FULL_422
- [ ] YBR_PARTIAL_420
- [ ] YBR_PARTIAL_422
- [ ] YBR_ICT (JPEG 2000)
- [ ] YBR_RCT (JPEG 2000)

---

## Priority 3: Enhancement Gaps

### 3.1 Overlay Data

**Current State:** Not supported.

#### Test Scenarios Needed

```
test/dcmix/overlay_test.exs
```

- [ ] Parse overlay data (60xx,3000)
- [ ] Extract overlay as binary mask
- [ ] Handle multiple overlays (6000, 6002, 6004, etc.)
- [ ] Overlay dimensions (60xx,0010 and 60xx,0011)
- [ ] Overlay origin (60xx,0050)
- [ ] Overlay in pixel data vs separate

---

### 3.2 Waveform Data

**Current State:** Not supported.

#### Test Scenarios Needed

```
test/dcmix/waveform_test.exs
```

- [ ] Parse WaveformSequence (5400,0100)
- [ ] Extract waveform samples
- [ ] Handle multiple channels
- [ ] Parse channel definitions
- [ ] Handle different sample interpretations

---

### 3.3 VOI LUT and Presentation State

**Current State:** Window/Level from tags is used, LUT sequences not supported.

#### Test Scenarios Needed

```
test/dcmix/voi_lut_test.exs
```

- [ ] Apply VOI LUT Sequence
- [ ] Apply Modality LUT Sequence
- [ ] Handle multiple window/level values
- [ ] Parse Softcopy Presentation State
- [ ] Apply presentation state to image

---

### 3.4 Structured Reports (SR)

**Current State:** Not supported.

#### Test Scenarios Needed

```
test/dcmix/sr_test.exs
```

- [ ] Parse SR document content tree
- [ ] Navigate content items
- [ ] Extract text values
- [ ] Extract coded values
- [ ] Handle SR templates (TID)

---

## Test Infrastructure Improvements

### Additional Test Helpers Needed

```elixir
# test/support/dicom_factory.ex
defmodule Dcmix.Test.DicomFactory do
  @moduledoc "Generate DICOM test data programmatically"

  def build_minimal_dicom(opts \\ [])
  def build_ct_image(rows, cols, opts \\ [])
  def build_mr_image(rows, cols, opts \\ [])
  def build_multi_frame(frames, rows, cols, opts \\ [])
  def build_sr_document(content_tree)
  def with_overlay(dataset, overlay_data)
  def with_compressed_pixels(dataset, transfer_syntax, pixel_data)
end
```

### Fixture Management

```elixir
# test/support/fixtures.ex
defmodule Dcmix.Test.Fixtures do
  @moduledoc "Manage test fixture files"

  @fixtures_url "https://github.com/robyoung/dicom-test-files/raw/main/data"

  def ensure_fixture(name)
  def download_fixture(name)
  def fixture_path(name)
end
```

### Property-Based Testing

Consider adding [StreamData](https://hexdocs.pm/stream_data) for property-based tests:

```elixir
# test/dcmix/property_test.exs
defmodule Dcmix.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "round-trip preserves all elements" do
    check all dataset <- dataset_generator() do
      {:ok, encoded} = Dcmix.encode(dataset)
      {:ok, decoded} = Dcmix.parse(encoded)
      assert datasets_equal?(dataset, decoded)
    end
  end
end
```

---

## Comparison with Reference Implementations

### DCMTK Test Categories

Based on [DCMTK documentation](https://blog.jriesmeier.com/2011/07/test-suite-for-dcmtk/):

| Module | Tests | Our Equivalent |
|--------|-------|----------------|
| ofstd | 23 | Elixir stdlib |
| dcmdata | 43 | parser_test, data_set_test |
| dcmiod | ? | Not applicable |
| dcmseg | ? | Not implemented |
| dcmnet | ? | Not implemented |
| dcmsr | ? | Not implemented |
| dcmrt | ? | Not implemented |

### dicom-rs Test Categories

Based on [dicom-rs repository](https://github.com/Enet4/dicom-rs):

| Crate | Tests | Our Equivalent |
|-------|-------|----------------|
| dicom-core | Unit tests | data_element_test, vr_test |
| dicom-encoding | Transfer syntax tests | parser_test (partial) |
| dicom-parser | Parser tests | parser_test |
| dicom-object | Object manipulation | data_set_test |
| dicom-pixeldata | Pixel data handling | pixel_data_test, export/image_test |
| dicom-dump | CLI tests | mix task tests |
| dicom-json | JSON conversion | export/json_test, import/json_test |

---

## Summary

### Tests to Add (Estimated Count)

| Priority | Category | Estimated Tests |
|----------|----------|-----------------|
| P1 | Compressed Transfer Syntaxes | 40-50 |
| P1 | Big Endian | 10-15 |
| P1 | File Meta Information | 20-25 |
| P1 | Multi-Frame Images | 15-20 |
| P2 | Deep Nested Sequences | 10-15 |
| P2 | Character Set Encoding | 30-40 |
| P2 | Padding Edge Cases | 10-15 |
| P2 | Photometric Interpretations | 15-20 |
| P3 | Overlay Data | 10-15 |
| P3 | Waveform Data | 10-15 |
| P3 | VOI LUT | 10-15 |
| P3 | Structured Reports | 20-30 |
| **Total** | | **200-275** |

### Fixtures to Acquire

Minimum set of additional test fixtures needed:

1. **Compressed files** (10 files) - from dicom-test-files or dcmtk conversion
2. **Big Endian file** (1 file) - dcmconv can create this
3. **Multi-frame files** (3 files) - uncompressed, compressed, enhanced
4. **Character set files** (6 files) - various encodings
5. **Overlay file** (1 file)
6. **Waveform file** (1 file) - ECG or similar

---

---

## Appendix A: Test Fixture Sources

### Primary Sources for DICOM Test Files

#### 1. dicom-test-files (Recommended)
**URL:** https://github.com/robyoung/dicom-test-files

This repository aggregates DICOM files from multiple sources specifically for library testing.

**Available files include:**
- `CT_small.dcm` - Small CT image
- `MR_small.dcm` - Small MR image
- `US_small.dcm` - Ultrasound image
- Various transfer syntaxes

**Usage in Elixir:**
```elixir
# Could create a mix task to download fixtures
# or reference them via URL in tests
@dicom_test_files_url "https://raw.githubusercontent.com/robyoung/dicom-test-files/main/data"
```

#### 2. GDCM Test Data
**URL:** https://sourceforge.net/projects/gdcm/files/gdcmData/

GDCM (Grassroots DICOM) maintains extensive test datasets including:
- Compressed transfer syntaxes (JPEG, JPEG2000, JPEG-LS, RLE)
- Big Endian files
- Multi-frame images
- Various photometric interpretations
- Character set examples

**Specific files of interest:**
```
gdcmData/
├── JPEG/
│   ├── DCMTK_JPEGExt_12Bits.dcm
│   ├── gdcm-JPEG-LossLess3a.dcm
│   └── ...
├── JPEG2000/
│   ├── NM_Kakadu44_SOTmarkerIssue.dcm
│   └── ...
├── RLE/
│   ├── ALOKA_SSD-8-MONO2-RLE-SQ.dcm
│   └── ...
└── US-RGB-8-epicard.dcm  (YBR_FULL)
```

#### 3. pydicom Test Files
**URL:** https://github.com/pydicom/pydicom/tree/main/src/pydicom/data/test_files

Python's pydicom library maintains test files at:
```
pydicom/data/test_files/
├── CT_small.dcm
├── MR_small.dcm
├── MR_small_RLE.dcm
├── MR_small_jpeg2k_lossless.dcm
├── MR_small_jpeg_ls_lossless.dcm
├── JPEG2000.dcm
├── JPEG2000_UNC.dcm
├── JPEG-lossy.dcm
├── JPEG-LL.dcm
├── RG1_UNCI.dcm (Implicit VR)
├── RG1_UNCL.dcm (Explicit VR Little Endian)
├── ExplVR_BigEnd.dcm (Big Endian)
├── ExplVR_BigEndNoMeta.dcm
├── charset_*.dcm (various character sets)
├── emri_small_*.dcm (enhanced MR multiframe)
└── ...
```

#### 4. dcm4che Test Resources
**URL:** https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test/src/main/resources

Java dcm4che library test resources.

#### 5. DICOM Sample Images from NEMA
**URL:** ftp://medical.nema.org/MEDICAL/Dicom/DataSets/

Official NEMA FTP server with compliance test images.

#### 6. Osirix DICOM Sample Images
**URL:** https://www.osirix-viewer.com/resources/dicom-image-library/

Large collection of real-world DICOM images (requires registration).

#### 7. Rubo Medical Imaging Test Files
**URL:** https://www.rubomedical.com/dicom_files/

Free DICOM sample files including:
- Various modalities (CT, MR, US, CR, DX)
- Different transfer syntaxes
- Multi-frame examples

---

## Appendix B: Detailed Test Scenarios

### B.1 JPEG Baseline Compression Tests

**File:** `test/dcmix/compression/jpeg_baseline_test.exs`

```elixir
defmodule Dcmix.Compression.JPEGBaselineTest do
  use ExUnit.Case, async: true

  # Fixture: pydicom's JPEG-lossy.dcm or gdcmData JPEG files
  @jpeg_baseline_fixture "test/fixtures/compressed/jpeg_baseline.dcm"

  describe "parsing JPEG baseline compressed DICOM" do
    test "reads file meta information correctly" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)

      # Transfer Syntax should be JPEG Baseline
      assert Dcmix.get_string(dataset, {0x0002, 0x0010}) ==
             "1.2.840.10008.1.2.4.50"
    end

    test "extracts encapsulated pixel data structure" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)
      pixel_element = Dcmix.DataSet.get(dataset, {0x7FE0, 0x0010})

      # Should have fragments, not raw binary
      assert is_list(pixel_element.value)
      assert length(pixel_element.value) >= 1
    end

    test "pixel data fragments start with JPEG SOI marker" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)
      pixel_element = Dcmix.DataSet.get(dataset, {0x7FE0, 0x0010})

      # Each fragment should be valid JPEG
      Enum.each(pixel_element.value, fn fragment ->
        # JPEG SOI marker is 0xFFD8
        assert <<0xFF, 0xD8, _rest::binary>> = fragment
      end)
    end

    test "basic offset table is present or empty" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)

      # Offset table is first item in encapsulated pixel data
      # Can be empty (zero length) or contain frame offsets
      {:ok, offset_table} = Dcmix.PixelData.get_offset_table(dataset)
      assert is_binary(offset_table) or is_nil(offset_table)
    end

    test "image dimensions match pixel data" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)

      rows = Dcmix.get(dataset, {0x0028, 0x0010})
      cols = Dcmix.get(dataset, {0x0028, 0x0011})

      # After decoding, pixel count should match
      {:ok, decoded} = Dcmix.PixelData.decode(dataset)
      samples_per_pixel = Dcmix.get(dataset, {0x0028, 0x0002}) || 1
      bits_allocated = Dcmix.get(dataset, {0x0028, 0x0100})
      bytes_per_sample = div(bits_allocated, 8)

      expected_size = rows * cols * samples_per_pixel * bytes_per_sample
      assert byte_size(decoded) == expected_size
    end
  end

  describe "JPEG baseline decoding" do
    test "decodes 8-bit grayscale JPEG" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)

      {:ok, pixels} = Dcmix.PixelData.decode(dataset)

      # Verify pixel values are in valid range
      assert is_binary(pixels)
      for <<pixel::8 <- pixels>> do
        assert pixel >= 0 and pixel <= 255
      end
    end

    test "decodes to correct photometric interpretation" do
      {:ok, dataset} = Dcmix.read_file(@jpeg_baseline_fixture)

      photometric = Dcmix.get_string(dataset, {0x0028, 0x0004})
      {:ok, pixels} = Dcmix.PixelData.decode(dataset)

      # JPEG baseline typically produces YBR_FULL or RGB
      assert photometric in ["MONOCHROME1", "MONOCHROME2", "RGB", "YBR_FULL"]
    end
  end
end
```

### B.2 RLE Compression Tests

**File:** `test/dcmix/compression/rle_test.exs`

```elixir
defmodule Dcmix.Compression.RLETest do
  use ExUnit.Case, async: true

  # Fixture: gdcmData/RLE/ or pydicom's MR_small_RLE.dcm
  @rle_fixture "test/fixtures/compressed/rle_lossless.dcm"

  describe "parsing RLE compressed DICOM" do
    test "identifies RLE transfer syntax" do
      {:ok, dataset} = Dcmix.read_file(@rle_fixture)

      assert Dcmix.get_string(dataset, {0x0002, 0x0010}) ==
             "1.2.840.10008.1.2.5"
    end

    test "extracts RLE segments from pixel data" do
      {:ok, dataset} = Dcmix.read_file(@rle_fixture)
      pixel_element = Dcmix.DataSet.get(dataset, {0x7FE0, 0x0010})

      # RLE has specific segment structure
      [first_fragment | _] = pixel_element.value

      # RLE header: number of segments (4 bytes) + 15 segment offsets (60 bytes)
      <<num_segments::32-little, _offsets::binary-size(60), _data::binary>> = first_fragment

      # Typically 1-3 segments for grayscale, more for RGB
      assert num_segments >= 1 and num_segments <= 15
    end
  end

  describe "RLE decoding" do
    test "decodes RLE to uncompressed pixels" do
      {:ok, dataset} = Dcmix.read_file(@rle_fixture)

      {:ok, decoded} = Dcmix.PixelData.decode(dataset)

      rows = Dcmix.get(dataset, {0x0028, 0x0010})
      cols = Dcmix.get(dataset, {0x0028, 0x0011})
      bits_allocated = Dcmix.get(dataset, {0x0028, 0x0100})
      samples = Dcmix.get(dataset, {0x0028, 0x0002}) || 1

      expected_size = rows * cols * samples * div(bits_allocated, 8)
      assert byte_size(decoded) == expected_size
    end

    test "RLE decoding is lossless (round-trip)" do
      # Create test data, compress, decompress, compare
      original_pixels = :crypto.strong_rand_bytes(256 * 256)

      {:ok, compressed} = Dcmix.Compression.RLE.encode(original_pixels, 256, 256, 8, 1)
      {:ok, decompressed} = Dcmix.Compression.RLE.decode(compressed, 256, 256, 8, 1)

      assert decompressed == original_pixels
    end
  end
end
```

### B.3 Big Endian Tests

**File:** `test/dcmix/parser/big_endian_test.exs`

```elixir
defmodule Dcmix.Parser.BigEndianTest do
  use ExUnit.Case, async: true

  # Fixture: pydicom's ExplVR_BigEnd.dcm
  @big_endian_fixture "test/fixtures/explicit_vr_big_endian.dcm"

  describe "parsing Explicit VR Big Endian" do
    test "identifies big endian transfer syntax" do
      {:ok, dataset} = Dcmix.read_file(@big_endian_fixture)

      # Note: File Meta is always Little Endian
      # Dataset uses Big Endian
      assert Dcmix.get_string(dataset, {0x0002, 0x0010}) ==
             "1.2.840.10008.1.2.2"
    end

    test "reads 16-bit integers correctly" do
      {:ok, dataset} = Dcmix.read_file(@big_endian_fixture)

      rows = Dcmix.get(dataset, {0x0028, 0x0010})
      cols = Dcmix.get(dataset, {0x0028, 0x0011})

      # Values should be reasonable image dimensions
      assert is_integer(rows) and rows > 0 and rows < 65535
      assert is_integer(cols) and cols > 0 and cols < 65535
    end

    test "reads 32-bit integers correctly" do
      {:ok, dataset} = Dcmix.read_file(@big_endian_fixture)

      # Find a UL (32-bit unsigned) element
      if element = Dcmix.DataSet.get(dataset, {0x0028, 0x0009}) do
        # FrameIncrementPointer
        assert is_integer(element.value) or is_tuple(element.value)
      end
    end

    test "reads floating point values correctly" do
      {:ok, dataset} = Dcmix.read_file(@big_endian_fixture)

      # PixelSpacing (DS) or other float values
      if spacing = Dcmix.get_string(dataset, {0x0028, 0x0030}) do
        [first | _] = String.split(spacing, "\\")
        {float_val, _} = Float.parse(first)
        assert is_float(float_val)
      end
    end

    test "reads pixel data with correct byte order" do
      {:ok, dataset} = Dcmix.read_file(@big_endian_fixture)

      bits_allocated = Dcmix.get(dataset, {0x0028, 0x0100})

      if bits_allocated == 16 do
        {:ok, pixels} = Dcmix.PixelData.get_pixels(dataset)

        # 16-bit pixels in big endian should be readable
        for <<pixel::16-big <- pixels>> do
          assert pixel >= 0
        end
      end
    end
  end

  describe "writing Explicit VR Big Endian" do
    test "writes 16-bit values in big endian byte order" do
      dataset = Dcmix.DataSet.new()
      |> Dcmix.DataSet.put_element({0x0028, 0x0010}, :US, 512)
      |> Dcmix.DataSet.put_element({0x0028, 0x0011}, :US, 512)

      {:ok, encoded} = Dcmix.encode(dataset, transfer_syntax: :explicit_vr_big_endian)

      # Find the encoded US value for Rows
      # In Big Endian, 512 = 0x0200 should be encoded as <<0x02, 0x00>>
      assert encoded =~ <<0x02, 0x00>>
    end

    test "round-trip preserves all values" do
      {:ok, original} = Dcmix.read_file(@big_endian_fixture)

      {:ok, encoded} = Dcmix.encode(original, transfer_syntax: :explicit_vr_big_endian)
      {:ok, decoded} = Dcmix.parse(encoded)

      # Compare key elements
      assert Dcmix.get(decoded, {0x0028, 0x0010}) == Dcmix.get(original, {0x0028, 0x0010})
      assert Dcmix.get(decoded, {0x0028, 0x0011}) == Dcmix.get(original, {0x0028, 0x0011})
    end
  end
end
```

### B.4 Multi-Frame Image Tests

**File:** `test/dcmix/pixel_data/multi_frame_test.exs`

```elixir
defmodule Dcmix.PixelData.MultiFrameTest do
  use ExUnit.Case, async: true

  # Fixtures needed:
  # - Uncompressed multi-frame (US or XA modality common)
  # - Compressed multi-frame (Enhanced MR/CT)
  @multiframe_uncompressed "test/fixtures/multiframe/us_multiframe.dcm"
  @multiframe_compressed "test/fixtures/multiframe/enhanced_mr.dcm"

  describe "parsing multi-frame images" do
    test "reads NumberOfFrames attribute" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      num_frames = Dcmix.get(dataset, {0x0028, 0x0008})

      assert is_integer(num_frames) or is_binary(num_frames)
      frames = if is_binary(num_frames), do: String.to_integer(num_frames), else: num_frames
      assert frames > 1
    end

    test "pixel data size matches frame count" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      rows = Dcmix.get(dataset, {0x0028, 0x0010})
      cols = Dcmix.get(dataset, {0x0028, 0x0011})
      frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()
      bits = Dcmix.get(dataset, {0x0028, 0x0100})
      samples = Dcmix.get(dataset, {0x0028, 0x0002}) || 1

      {:ok, pixels} = Dcmix.PixelData.get_pixels(dataset)

      expected_size = rows * cols * frames * samples * div(bits, 8)
      assert byte_size(pixels) == expected_size
    end

    defp to_integer(val) when is_integer(val), do: val
    defp to_integer(val) when is_binary(val), do: String.to_integer(String.trim(val))
  end

  describe "extracting individual frames" do
    test "extracts first frame" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      {:ok, frame} = Dcmix.PixelData.get_frame(dataset, 0)

      rows = Dcmix.get(dataset, {0x0028, 0x0010})
      cols = Dcmix.get(dataset, {0x0028, 0x0011})
      bits = Dcmix.get(dataset, {0x0028, 0x0100})
      samples = Dcmix.get(dataset, {0x0028, 0x0002}) || 1

      expected_frame_size = rows * cols * samples * div(bits, 8)
      assert byte_size(frame) == expected_frame_size
    end

    test "extracts middle frame" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()
      middle_frame = div(num_frames, 2)

      {:ok, frame} = Dcmix.PixelData.get_frame(dataset, middle_frame)
      assert is_binary(frame)
    end

    test "extracts last frame" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()

      {:ok, frame} = Dcmix.PixelData.get_frame(dataset, num_frames - 1)
      assert is_binary(frame)
    end

    test "returns error for invalid frame index" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()

      assert {:error, _} = Dcmix.PixelData.get_frame(dataset, num_frames)
      assert {:error, _} = Dcmix.PixelData.get_frame(dataset, -1)
    end

    test "extracts all frames as list" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      {:ok, frames} = Dcmix.PixelData.get_all_frames(dataset)

      num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()
      assert length(frames) == num_frames
    end

    defp to_integer(val) when is_integer(val), do: val
    defp to_integer(val) when is_binary(val), do: String.to_integer(String.trim(val))
  end

  describe "multi-frame compressed images" do
    test "extracts frames from encapsulated pixel data" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_compressed)

      # Enhanced MR may have per-frame fragments
      {:ok, frame} = Dcmix.PixelData.get_frame(dataset, 0)
      assert is_binary(frame)
    end

    test "uses basic offset table when available" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_compressed)

      {:ok, offset_table} = Dcmix.PixelData.get_offset_table(dataset)

      if byte_size(offset_table) > 0 do
        # Each offset is 4 bytes (32-bit)
        num_offsets = div(byte_size(offset_table), 4)
        num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()

        # Offset table should have one entry per frame
        assert num_offsets == num_frames
      end
    end

    defp to_integer(val) when is_integer(val), do: val
    defp to_integer(val) when is_binary(val), do: String.to_integer(String.trim(val))
  end

  describe "exporting multi-frame to images" do
    test "exports specific frame to PNG" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      tmp_path = Path.join(System.tmp_dir!(), "frame_5.png")

      try do
        :ok = Dcmix.to_image(dataset, tmp_path, frame: 5)
        assert File.exists?(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "exports all frames to numbered PNGs" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_uncompressed)

      tmp_dir = Path.join(System.tmp_dir!(), "frames_#{:rand.uniform(100000)}")
      File.mkdir_p!(tmp_dir)

      try do
        :ok = Dcmix.to_image(dataset, Path.join(tmp_dir, "frame_%04d.png"), all_frames: true)

        num_frames = Dcmix.get(dataset, {0x0028, 0x0008}) |> to_integer()
        files = File.ls!(tmp_dir)
        assert length(files) == num_frames
      after
        File.rm_rf!(tmp_dir)
      end
    end

    defp to_integer(val) when is_integer(val), do: val
    defp to_integer(val) when is_binary(val), do: String.to_integer(String.trim(val))
  end
end
```

### B.5 Character Set Tests

**File:** `test/dcmix/charset_test.exs`

```elixir
defmodule Dcmix.CharsetTest do
  use ExUnit.Case, async: true

  # Fixtures from pydicom: charset_*.dcm files
  # Or create programmatically

  describe "ISO-IR 100 (Latin-1)" do
    @latin1_fixture "test/fixtures/charset/latin1.dcm"

    test "reads Latin-1 encoded patient name" do
      {:ok, dataset} = Dcmix.read_file(@latin1_fixture)

      charset = Dcmix.get_string(dataset, {0x0008, 0x0005})
      assert charset == "ISO_IR 100"

      # Should contain accented characters like é, ñ, ü
      name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      assert is_binary(name)
    end
  end

  describe "ISO_IR 192 (UTF-8)" do
    @utf8_fixture "test/fixtures/charset/utf8.dcm"

    test "reads UTF-8 encoded text" do
      {:ok, dataset} = Dcmix.read_file(@utf8_fixture)

      charset = Dcmix.get_string(dataset, {0x0008, 0x0005})
      assert charset == "ISO_IR 192"

      # Should handle any Unicode
      name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      assert String.valid?(name)
    end

    test "writes UTF-8 encoded text" do
      dataset = Dcmix.DataSet.new()
      |> Dcmix.DataSet.put_element({0x0008, 0x0005}, :CS, "ISO_IR 192")
      |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "日本語^テスト")

      {:ok, encoded} = Dcmix.encode(dataset)
      {:ok, decoded} = Dcmix.parse(encoded)

      assert Dcmix.get_string(decoded, {0x0010, 0x0010}) == "日本語^テスト"
    end
  end

  describe "Japanese (ISO 2022 IR 87)" do
    @japanese_fixture "test/fixtures/charset/japanese_kanji.dcm"

    test "reads Japanese Kanji characters" do
      {:ok, dataset} = Dcmix.read_file(@japanese_fixture)

      charset = Dcmix.get_string(dataset, {0x0008, 0x0005})
      # Multi-valued: default + Japanese
      assert charset =~ "ISO 2022 IR 87" or charset =~ "IR 87"

      name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      assert is_binary(name)
    end

    test "handles escape sequences in person name" do
      {:ok, dataset} = Dcmix.read_file(@japanese_fixture)

      # Japanese PN can have Alphabetic=Ideographic=Phonetic components
      # with escape sequences between them
      name = Dcmix.get_string(dataset, {0x0010, 0x0010})

      # Should not contain raw escape bytes in final output
      refute name =~ <<0x1B>>
    end
  end

  describe "Korean (ISO 2022 IR 149)" do
    @korean_fixture "test/fixtures/charset/korean.dcm"

    test "reads Korean characters" do
      {:ok, dataset} = Dcmix.read_file(@korean_fixture)

      name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      assert is_binary(name)
    end
  end

  describe "Chinese GB18030" do
    @chinese_fixture "test/fixtures/charset/chinese_gb18030.dcm"

    test "reads simplified Chinese characters" do
      {:ok, dataset} = Dcmix.read_file(@chinese_fixture)

      charset = Dcmix.get_string(dataset, {0x0008, 0x0005})
      assert charset == "GB18030"

      name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      assert is_binary(name)
    end
  end
end
```

---

## References

- [DCMTK Test Suite](https://blog.jriesmeier.com/2011/07/test-suite-for-dcmtk/)
- [dicom-rs Repository](https://github.com/Enet4/dicom-rs)
- [dicom-test-files](https://github.com/robyoung/dicom-test-files)
- [pydicom Test Files](https://github.com/pydicom/pydicom/tree/main/src/pydicom/data/test_files)
- [GDCM Test Data](https://sourceforge.net/projects/gdcm/files/gdcmData/)
- [DICOM Standard](https://www.dicomstandard.org/current)
- [DICOM Part 5 - Data Structures](https://dicom.nema.org/medical/dicom/current/output/html/part05.html)
- [DICOM Part 10 - Media Storage](https://dicom.nema.org/medical/dicom/current/output/html/part10.html)
