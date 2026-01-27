# Transfer Syntax Support

Dcmix supports reading and writing DICOM files with various transfer syntaxes.

## Fully Supported

These transfer syntaxes are fully supported for both reading and writing:

| Transfer Syntax | UID | Description |
|----------------|-----|-------------|
| Implicit VR Little Endian | 1.2.840.10008.1.2 | Default DICOM transfer syntax |
| Explicit VR Little Endian | 1.2.840.10008.1.2.1 | Most common modern transfer syntax |
| Explicit VR Big Endian | 1.2.840.10008.1.2.2 | Retired, but still supported |

## Encapsulated (Stored Only)

For compressed transfer syntaxes, Dcmix can read and write the encapsulated pixel data as-is (without decompression). The pixel data is stored as fragments that can be extracted or passed through.

| Transfer Syntax | UID | Notes |
|----------------|-----|-------|
| JPEG Baseline | 1.2.840.10008.1.2.4.50 | Lossy compression |
| JPEG Lossless | 1.2.840.10008.1.2.4.70 | Lossless compression |
| JPEG 2000 Lossless | 1.2.840.10008.1.2.4.90 | Lossless compression |
| JPEG 2000 | 1.2.840.10008.1.2.4.91 | Lossy compression |
| RLE Lossless | 1.2.840.10008.1.2.5 | Run-length encoding |

## Working with Encapsulated Pixel Data

When reading a file with compressed pixel data:

```elixir
{:ok, dataset} = Dcmix.read_file("compressed.dcm")

# Check the transfer syntax
transfer_syntax = Dcmix.get_string(dataset, "TransferSyntaxUID")
# => "1.2.840.10008.1.2.4.50" (JPEG Baseline)

# Extract the raw encapsulated data (compressed bytes)
{:ok, fragments} = Dcmix.PixelData.extract_fragments(dataset)

# The fragments contain the compressed JPEG/JPEG2000/RLE data
# Use external tools to decompress if needed
```

When writing encapsulated pixel data:

```elixir
# Inject pre-compressed fragments
dataset = Dcmix.PixelData.inject_fragments(dataset, fragments)

# Write with appropriate transfer syntax
:ok = Dcmix.write_file(dataset, "output.dcm",
  transfer_syntax: "1.2.840.10008.1.2.4.50")
```

## Transfer Syntax Selection

When writing files, Dcmix will:

1. Use the transfer syntax specified in write options if provided
2. Otherwise, preserve the original file's transfer syntax
3. Default to Explicit VR Little Endian for new datasets

```elixir
# Specify transfer syntax explicitly
Dcmix.write_file(dataset, "output.dcm",
  transfer_syntax: :implicit_vr_little_endian)

# Or use the UID directly
Dcmix.write_file(dataset, "output.dcm",
  transfer_syntax: "1.2.840.10008.1.2")
```

## Future Support

Pixel data decompression (decoding JPEG, JPEG 2000, RLE to raw pixels) is planned for a future release. This will enable:

- Direct image export from compressed DICOM files
- Transfer syntax conversion (transcoding)
- Full pixel data manipulation for compressed images
