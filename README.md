# Dcmix

A DICOM library for Elixir - read, write, and manipulate DICOM files.

Dcmix (pronounced "DCM-icks") is a pure Elixir implementation for working with DICOM medical imaging files, inspired by [dcmtk](https://dicom.offis.de/dcmtk.php.en) and [dicom-rs](https://github.com/Enet4/dicom-rs).

> **⚠️ Experimental Status**
>
> This project is in an **experimental stage** and is not yet recommended for production use.
> A significant portion of this codebase was generated with AI assistance and has not been
> fully vetted for correctness, security, or compliance with the DICOM standard. Use at your
> own risk and please report any issues you encounter.

## Features

- Read and parse DICOM Part 10 files
- Write DICOM files with proper file meta information
- Multiple transfer syntax support (Implicit VR LE, Explicit VR LE/BE)
- Export to JSON, XML, and image formats (PNG, PPM, PGM)
- Import from JSON, XML, and image files
- Human-readable dump output (dcmdump style)
- Private tag support
- Mix tasks for CLI usage

## Installation

Add `dcmix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dcmix, github: "avandra/dcmix"}
  ]
end
```

## Quick Start

### Reading DICOM Files

```elixir
# Read a DICOM file
{:ok, dataset} = Dcmix.read_file("patient.dcm")

# Get element values
patient_name = Dcmix.get_string(dataset, "PatientName")
rows = Dcmix.get(dataset, {0x0028, 0x0010})

# Dump contents
IO.puts(Dcmix.dump(dataset))
```

### Writing DICOM Files

```elixir
dataset = Dcmix.new()
|> Dcmix.put({0x0010, 0x0010}, :PN, "Doe^John")
|> Dcmix.put({0x0010, 0x0020}, :LO, "12345")
|> Dcmix.put({0x0008, 0x0060}, :CS, "CT")

:ok = Dcmix.write_file(dataset, "output.dcm")
```

### Export Formats

```elixir
# Export to JSON (DICOM JSON Model)
{:ok, json} = Dcmix.to_json(dataset, pretty: true)

# Export to XML (Native DICOM Model)
{:ok, xml} = Dcmix.to_xml(dataset)

# Export pixel data to image
:ok = Dcmix.to_image(dataset, "output.png")
```

### CLI Tools

```bash
mix dcmix.dump patient.dcm
mix dcmix.to_json --pretty patient.dcm output.json
mix dcmix.to_xml patient.dcm output.xml
mix dcmix.to_image --window auto patient.dcm output.png
```

## Documentation

- [Detailed Usage Guide](docs/USAGE.md) - Pixel data, private tags, import operations
- [Transfer Syntax Support](docs/TRANSFER_SYNTAXES.md) - Supported transfer syntaxes
- [Roadmap](docs/ROADMAP.md) - Current and planned features

## Development

```bash
mix deps.get          # Install dependencies
mix test              # Run tests
mix test --cover      # Run tests with coverage
mix credo --strict    # Static analysis
mix sobelow           # Security analysis
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [dcmtk](https://dicom.offis.de/dcmtk.php.en) and [dicom-rs](https://github.com/Enet4/dicom-rs)
- DICOM standard from [NEMA](https://www.dicomstandard.org/)
