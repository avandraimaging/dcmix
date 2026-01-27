# Dcmix

A DICOM library for Elixir - read, write, and manipulate DICOM files.

Dcmix (pronounced "DCM-icks") is a port of functionality from [dcmtk](https://dicom.offis.de/dcmtk.php.en) and [dicom-rs](https://github.com/Enet4/dicom-rs), focused on DICOM file operations.

## Features

- Read and parse DICOM Part 10 files
- Write DICOM files with proper file meta information
- Multiple transfer syntax support (Implicit VR LE, Explicit VR LE/BE)
- Export to JSON (DICOM JSON Model - PS3.18 F.2) and XML (Native DICOM Model - PS3.19)
- Human-readable dump output (similar to dcmdump)
- Pixel data extraction and injection
- Private tag support
- Mix tasks for CLI usage

## Installation

Add `dcmix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dcmix, "~> 0.1.0"}
  ]
end
```

## Usage

### Reading DICOM Files

```elixir
# Read a DICOM file
{:ok, dataset} = Dcmix.read_file("/path/to/file.dcm")

# Get element values by tag
patient_name = Dcmix.get_string(dataset, {0x0010, 0x0010})
patient_name = Dcmix.get_string(dataset, "PatientName")  # or by keyword

# Get numeric values
rows = Dcmix.get(dataset, {0x0028, 0x0010})

# Dump contents
IO.puts(Dcmix.dump(dataset))
```

### Writing DICOM Files

```elixir
# Create a new dataset
dataset = Dcmix.new()
|> Dcmix.put({0x0010, 0x0010}, :PN, "Doe^John")
|> Dcmix.put({0x0010, 0x0020}, :LO, "12345")
|> Dcmix.put({0x0008, 0x0060}, :CS, "CT")

# Write to file
:ok = Dcmix.write_file(dataset, "/path/to/output.dcm")
```

### Exporting to JSON/XML

```elixir
# Export to JSON (DICOM JSON Model)
{:ok, json} = Dcmix.to_json(dataset, pretty: true)

# Export to XML (Native DICOM Model)
{:ok, xml} = Dcmix.to_xml(dataset)
```

### Pixel Data

```elixir
# Extract pixel data
{:ok, pixel_bytes} = Dcmix.PixelData.extract(dataset)

# Get pixel data info
info = Dcmix.PixelData.info(dataset)
# => %{rows: 512, columns: 512, bits_allocated: 16, ...}

# Inject pixel data back
dataset = Dcmix.PixelData.inject(dataset, new_pixel_bytes)
```

### Private Tags

```elixir
# Register a private creator and add data
{dataset, block} = Dcmix.PrivateTag.register_creator(dataset, 0x0009, "MY_COMPANY")
dataset = Dcmix.PrivateTag.put(dataset, 0x0009, "MY_COMPANY", 0x01, :LO, "Custom Data")

# Read private data
value = Dcmix.PrivateTag.get(dataset, 0x0009, "MY_COMPANY", 0x01)
```

## Mix Tasks

```bash
# Dump DICOM file contents
mix dcmix.dump patient.dcm

# Convert to JSON
mix dcmix.to_json patient.dcm output.json
mix dcmix.to_json --pretty patient.dcm

# Convert to XML
mix dcmix.to_xml patient.dcm output.xml
```

## Transfer Syntax Support

Dcmix supports the following transfer syntaxes:

| Transfer Syntax | UID | Status |
|----------------|-----|--------|
| Implicit VR Little Endian | 1.2.840.10008.1.2 | Supported |
| Explicit VR Little Endian | 1.2.840.10008.1.2.1 | Supported |
| Explicit VR Big Endian | 1.2.840.10008.1.2.2 | Supported |
| JPEG Baseline | 1.2.840.10008.1.2.4.50 | Stored as encapsulated |
| JPEG Lossless | 1.2.840.10008.1.2.4.70 | Stored as encapsulated |
| JPEG 2000 | 1.2.840.10008.1.2.4.90/91 | Stored as encapsulated |
| RLE Lossless | 1.2.840.10008.1.2.5 | Stored as encapsulated |

For compressed transfer syntaxes, pixel data is stored as encapsulated fragments. Decompression requires external tools.

## Dependencies

- `jason` - JSON encoding

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Compile
mix compile
```

## License

MIT License

## Acknowledgments

- Inspired by [dcmtk](https://dicom.offis.de/dcmtk.php.en) and [dicom-rs](https://github.com/Enet4/dicom-rs)
- DICOM standard from [NEMA](https://www.dicomstandard.org/)
