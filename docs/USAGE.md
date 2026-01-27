# Detailed Usage Guide

This guide covers advanced usage of Dcmix beyond the basics in the README.

## Table of Contents

- [Pixel Data Operations](#pixel-data-operations)
- [Private Tags](#private-tags)
- [Import Operations](#import-operations)
- [Mix Tasks Reference](#mix-tasks-reference)

## Pixel Data Operations

### Extracting Pixel Data

```elixir
{:ok, dataset} = Dcmix.read_file("image.dcm")

# Extract raw pixel bytes
{:ok, pixel_bytes} = Dcmix.PixelData.extract(dataset)

# Get pixel data metadata
info = Dcmix.PixelData.info(dataset)
# => %{
#      rows: 512,
#      columns: 512,
#      bits_allocated: 16,
#      bits_stored: 12,
#      high_bit: 11,
#      pixel_representation: 0,
#      samples_per_pixel: 1,
#      photometric_interpretation: "MONOCHROME2"
#    }
```

### Injecting Pixel Data

```elixir
# Replace pixel data in a dataset
dataset = Dcmix.PixelData.inject(dataset, new_pixel_bytes)

# The pixel data metadata (rows, columns, etc.) should match
# Update metadata if dimensions changed:
dataset = dataset
|> Dcmix.put({0x0028, 0x0010}, :US, new_rows)
|> Dcmix.put({0x0028, 0x0011}, :US, new_columns)
|> Dcmix.PixelData.inject(new_pixel_bytes)
```

### Image Export Options

```elixir
# Export to PNG (default)
:ok = Dcmix.to_image(dataset, "output.png")

# Export specific frame from multi-frame image
:ok = Dcmix.to_image(dataset, "frame5.png", frame: 5)

# Windowing options for grayscale images
:ok = Dcmix.to_image(dataset, "auto.png", window: :auto)      # Use VOI LUT or min/max
:ok = Dcmix.to_image(dataset, "minmax.png", window: :min_max) # Based on actual values
:ok = Dcmix.to_image(dataset, "raw.png", window: :none)       # No windowing

# Explicit window center and width (e.g., CT soft tissue)
:ok = Dcmix.to_image(dataset, "soft_tissue.png", window: {40, 400})

# Export to PPM (color) or PGM (grayscale)
:ok = Dcmix.to_image(dataset, "output.pgm")
:ok = Dcmix.to_image(dataset, "output.ppm")
```

## Private Tags

Private tags allow vendors to store proprietary data in DICOM files.

### Reading Private Tags

```elixir
{:ok, dataset} = Dcmix.read_file("vendor_image.dcm")

# Find private creator blocks
creators = Dcmix.PrivateTag.list_creators(dataset)
# => [%{group: 0x0009, creator: "VENDOR_NAME", block: 0x10}, ...]

# Read a private element
value = Dcmix.PrivateTag.get(dataset, 0x0009, "VENDOR_NAME", 0x01)
```

### Writing Private Tags

```elixir
# Register a private creator and get the assigned block
{dataset, block} = Dcmix.PrivateTag.register_creator(dataset, 0x0009, "MY_COMPANY")

# Add private elements (element numbers 0x01-0xFF within the block)
dataset = dataset
|> Dcmix.PrivateTag.put(0x0009, "MY_COMPANY", 0x01, :LO, "Custom String")
|> Dcmix.PrivateTag.put(0x0009, "MY_COMPANY", 0x02, :DS, "123.456")
|> Dcmix.PrivateTag.put(0x0009, "MY_COMPANY", 0x10, :OB, <<binary_data::binary>>)
```

### Private Tag Conventions

- Groups must be odd numbers (0x0009, 0x0011, etc.)
- Creator identification is stored at (group, 0x00XX) where XX is the block number
- Private elements use tags (group, 0xXXYY) where XX is block and YY is element

## Import Operations

### Import from JSON

```elixir
# From JSON string
json = ~s({"00100010": {"vr": "PN", "Value": [{"Alphabetic": "Doe^John"}]}})
{:ok, dataset} = Dcmix.from_json(json)

# From file
{:ok, dataset} = Dcmix.from_json_file("patient.json")
```

### Import from XML

```elixir
# From XML string (Native DICOM Model)
xml = """
<?xml version="1.0" encoding="UTF-8"?>
<NativeDicomModel>
  <DicomAttribute tag="00100010" vr="PN">
    <PersonName>
      <Alphabetic>
        <FamilyName>Doe</FamilyName>
        <GivenName>John</GivenName>
      </Alphabetic>
    </PersonName>
  </DicomAttribute>
</NativeDicomModel>
"""
{:ok, dataset} = Dcmix.from_xml(xml)

# From file
{:ok, dataset} = Dcmix.from_xml_file("patient.xml")
```

### Import Pixel Data from Image

```elixir
# Start with an existing dataset (for metadata) or create new
{:ok, dataset} = Dcmix.read_file("template.dcm")

# Import pixel data from an image file
{:ok, dataset} = Dcmix.from_image(dataset, "new_pixels.png")

# For a new dataset, set required pixel metadata first
dataset = Dcmix.new()
|> Dcmix.put({0x0028, 0x0010}, :US, 512)  # Rows
|> Dcmix.put({0x0028, 0x0011}, :US, 512)  # Columns
|> Dcmix.put({0x0028, 0x0100}, :US, 8)    # Bits Allocated
|> Dcmix.put({0x0028, 0x0101}, :US, 8)    # Bits Stored
|> Dcmix.put({0x0028, 0x0102}, :US, 7)    # High Bit

{:ok, dataset} = Dcmix.from_image(dataset, "image.png")
```

## Mix Tasks Reference

### dcmix.dump

Display DICOM file contents in human-readable format.

```bash
mix dcmix.dump patient.dcm
mix dcmix.dump --max-length 100 patient.dcm  # Truncate long values
```

### dcmix.to_json

Convert DICOM to JSON (DICOM JSON Model PS3.18 F.2).

```bash
mix dcmix.to_json patient.dcm                    # Output to stdout
mix dcmix.to_json patient.dcm output.json        # Output to file
mix dcmix.to_json --pretty patient.dcm           # Pretty-printed JSON
```

### dcmix.to_xml

Convert DICOM to XML (Native DICOM Model PS3.19).

```bash
mix dcmix.to_xml patient.dcm                     # Output to stdout
mix dcmix.to_xml patient.dcm output.xml          # Output to file
```

### dcmix.to_image

Export pixel data to image file.

```bash
mix dcmix.to_image patient.dcm output.png
mix dcmix.to_image --frame 0 patient.dcm output.png
mix dcmix.to_image --window auto patient.dcm output.png
mix dcmix.to_image --window 400,40 patient.dcm output.png  # CT soft tissue
mix dcmix.to_image --format pgm patient.dcm output.pgm
```

### dcmix.from_json

Create DICOM file from JSON.

```bash
mix dcmix.from_json input.json output.dcm
```

### dcmix.from_xml

Create DICOM file from XML.

```bash
mix dcmix.from_xml input.xml output.dcm
```

### dcmix.from_image

Import pixel data from image into DICOM file.

```bash
mix dcmix.from_image template.dcm new_pixels.png output.dcm
```
