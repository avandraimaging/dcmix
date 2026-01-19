# AGENTS.md - AI Agent Guidelines for Dcmix

## Project Overview

**Dcmix** is a pure Elixir DICOM library that aims to provide functionality similar to [dcmtk](https://dcmtk.org/) and [dicom-rs](https://github.com/Enet4/dicom-rs). It enables reading, writing, parsing, and manipulating DICOM files without any native dependencies.

### Core Philosophy

- **Pure Elixir**: No NIFs, ports, or native code dependencies. All functionality must be implemented in Elixir/Erlang.
- **Feature Parity**: Aim to match the functionality of dcmtk and dicom-rs where practical
- **Standards Compliance**: Follow DICOM PS3 specifications (PS3.5, PS3.10, PS3.18, PS3.19)
- **Modern Elixir**: Follow current Elixir library conventions and best practices

## Project Structure

```
lib/
├── dcmix.ex                    # Main public API
├── dcmix/
│   ├── data_element.ex         # DICOM Data Element struct
│   ├── data_set.ex             # DICOM DataSet (collection of elements)
│   ├── dictionary.ex           # DICOM Data Dictionary
│   ├── parser.ex               # DICOM file parser
│   ├── parser/
│   │   ├── explicit_vr.ex      # Explicit VR parsing
│   │   ├── implicit_vr.ex      # Implicit VR parsing
│   │   └── transfer_syntax.ex  # Transfer syntax handling
│   ├── writer.ex               # DICOM file writer
│   ├── writer/
│   │   ├── explicit_vr.ex      # Explicit VR encoding
│   │   └── implicit_vr.ex      # Implicit VR encoding
│   ├── pixel_data.ex           # Pixel data handling
│   ├── private_tag.ex          # Private tag support
│   ├── tag.ex                  # Tag utilities
│   ├── vr.ex                   # Value Representation handling
│   ├── export/                 # Export functionality
│   │   ├── json.ex             # DICOM JSON Model (PS3.18 F.2)
│   │   ├── xml.ex              # Native DICOM Model XML (PS3.19)
│   │   ├── text.ex             # Human-readable dump
│   │   └── image.ex            # Pixel data to image export
│   └── import/                 # Import functionality
│       ├── json.ex             # JSON to DICOM (inverse of export)
│       ├── xml.ex              # XML to DICOM (inverse of export)
│       └── image.ex            # Image to DICOM (like img2dcm)
└── mix/tasks/                  # Mix tasks (CLI tools)
    ├── dcmix.dump.ex           # dcmdump equivalent
    ├── dcmix.to_json.ex        # dcm2json equivalent
    ├── dcmix.to_xml.ex         # dcm2xml equivalent
    ├── dcmix.to_image.ex       # dcm2pnm equivalent
    ├── dcmix.from_json.ex      # json2dcm equivalent
    ├── dcmix.from_xml.ex       # xml2dcm equivalent
    └── dcmix.from_image.ex     # img2dcm equivalent
```

## Quality Requirements

### Test Coverage

- **Minimum threshold: 90%**
- Run tests with coverage: `MIX_ENV=test mix test --cover`
- All new features must include comprehensive tests
- Test edge cases, error conditions, and boundary values
- Use async tests where possible for performance

### Static Analysis

#### Credo (Code Quality)
```bash
mix credo --strict
```
- No warnings or fatal errors allowed
- Readability and design suggestions are acceptable but should be addressed when practical
- Key rules:
  - Function nesting depth max 2
  - Group function clauses together
  - Alphabetical alias ordering (when practical)

#### Sobelow (Security)
```bash
mix sobelow
```
- Must pass with no security warnings
- No hardcoded secrets
- No unsafe deserialization
- No command injection vulnerabilities

### Compilation
```bash
mix compile --warnings-as-errors
```
- All warnings are treated as errors
- No compiler warnings allowed

## Coding Standards

### Module Structure

```elixir
defmodule Dcmix.Example do
  @moduledoc """
  Brief description of the module.

  ## Usage

      {:ok, result} = Dcmix.Example.function(args)
  """

  # 1. Aliases (alphabetically ordered)
  alias Dcmix.DataElement
  alias Dcmix.DataSet

  # 2. Module attributes
  @some_constant "value"

  # 3. Public functions with @doc and @spec
  @doc """
  Description of the function.
  """
  @spec public_function(term()) :: {:ok, term()} | {:error, term()}
  def public_function(arg) do
    # implementation
  end

  # 4. Private functions
  defp private_helper(arg) do
    # implementation
  end
end
```

### Error Handling

- Use tagged tuples: `{:ok, result}` or `{:error, reason}`
- Error reasons should be descriptive tuples: `{:file_read_error, :enoent}`
- Avoid raising exceptions except for programmer errors
- Use `with` for chaining operations that can fail

### Binary Pattern Matching

DICOM parsing relies heavily on binary pattern matching:

```elixir
# Little-endian 16-bit values
<<group::16-little, element::16-little, rest::binary>> = data

# Big-endian values
<<value::32-big>> = data

# VR as 2-byte string
<<vr::binary-size(2), rest::binary>> = data
```

### Tags

Tags are represented as tuples: `{group, element}` where both are integers.

```elixir
# PatientName tag
{0x0010, 0x0010}

# PixelData tag
{0x7FE0, 0x0010}
```

## Feature Implementation Guidelines

### Adding New Import/Export Formats

1. Create module in `lib/dcmix/import/` or `lib/dcmix/export/`
2. Add public API function in `lib/dcmix.ex`
3. Create mix task in `lib/mix/tasks/`
4. Add comprehensive tests in corresponding test directory
5. Follow existing patterns (see `json.ex`, `xml.ex` for examples)

### Adding Transfer Syntax Support

1. Add UID to `lib/dcmix/parser/transfer_syntax.ex`
2. Implement encoding/decoding if needed
3. Add tests with sample DICOM files

### Mix Task Pattern

```elixir
defmodule Mix.Tasks.Dcmix.Example do
  @shortdoc "Brief description"

  @moduledoc """
  Full documentation with usage examples.

  ## Usage

      mix dcmix.example <input> <output>

  ## Options

      -o, --option    Description of option
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = OptionParser.parse(args,
      strict: [option: :string],
      aliases: [o: :option]
    )

    case files do
      [input, output] ->
        do_conversion(input, output, opts)

      _ ->
        Mix.shell().error("Usage: mix dcmix.example <input> <output>")
        exit({:shutdown, 1})
    end
  end
end
```

## Dependencies

Current dependencies (all pure Elixir/Erlang):

- **jason** - JSON encoding/decoding
- **png** - PNG image encoding (pure Erlang)
- **credo** - Static code analysis (dev/test only)
- **sobelow** - Security analysis (dev/test only)

### Adding New Dependencies

Before adding a dependency:
1. Verify it's pure Elixir/Erlang (no NIFs or ports)
2. Check for active maintenance and security updates
3. Evaluate if the functionality can be implemented in-house
4. Prefer well-established, minimal dependencies

## Reference Implementations

When implementing DICOM functionality, refer to:

- **dcmtk**: C++ reference implementation - https://dcmtk.org/
- **dicom-rs**: Rust implementation - https://github.com/Enet4/dicom-rs
- **DICOM Standard**: https://www.dicomstandard.org/current

### dcmtk Tool Equivalents

| dcmtk Tool | Dcmix Mix Task | Status |
|------------|----------------|--------|
| dcmdump | mix dcmix.dump | ✅ |
| dcm2json | mix dcmix.to_json | ✅ |
| dcm2xml | mix dcmix.to_xml | ✅ |
| dcm2pnm | mix dcmix.to_image | ✅ |
| json2dcm | mix dcmix.from_json | ✅ |
| xml2dcm | mix dcmix.from_xml | ✅ |
| img2dcm | mix dcmix.from_image | ✅ |
| dcmconv | - | Planned |
| dcmodify | - | Planned |
| dcmftest | - | Planned |

## Testing Guidelines

### Test File Organization

```
test/
├── dcmix_test.exs              # Main API tests
├── dcmix/
│   ├── data_set_test.exs
│   ├── parser_test.exs
│   ├── export/
│   │   ├── json_test.exs
│   │   └── xml_test.exs
│   └── import/
│       ├── json_test.exs
│       ├── xml_test.exs
│       └── image_test.exs
├── mix/tasks/
│   └── dcmix_*.exs
└── fixtures/                   # Test DICOM files
    └── *.dcm
```

### Test Patterns

```elixir
defmodule Dcmix.Example.Test do
  use ExUnit.Case, async: true

  alias Dcmix.Example

  @fixtures_path "test/fixtures"

  describe "function_name/1" do
    test "handles normal case" do
      assert {:ok, result} = Example.function_name(input)
      assert result == expected
    end

    test "handles edge case" do
      assert {:error, reason} = Example.function_name(bad_input)
    end
  end
end
```

### Mix Task Testing

```elixir
defmodule Mix.Tasks.Dcmix.ExampleTest do
  use ExUnit.Case, async: false  # Mix tasks are not async-safe

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "converts successfully" do
    Mix.Tasks.Dcmix.Example.run([@input, @output])
    assert_received {:mix_shell, :info, [message]}
    assert message =~ "Written to"
  end

  test "shows error for missing file" do
    assert catch_exit(Mix.Tasks.Dcmix.Example.run(["nonexistent"])) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}
    assert message =~ "File not found"
  end
end
```

## Common Tasks

### Running All Quality Checks

```bash
mix compile --warnings-as-errors && \
mix credo --strict && \
mix sobelow && \
MIX_ENV=test mix test --cover
```

### Generating Documentation

```bash
mix docs
```

### Formatting Code

```bash
mix format
```

## Notes for AI Agents

1. **Always run tests** after making changes: `mix test`
2. **Check coverage** before completing: `MIX_ENV=test mix test --cover`
3. **Run credo** to ensure code quality: `mix credo --strict`
4. **No NIFs or ports** - if a feature seems to require native code, find a pure Elixir solution
5. **Follow existing patterns** - look at similar modules for implementation guidance
6. **Update tests** - new code requires new tests, aim for edge case coverage
7. **Keep functions focused** - avoid deep nesting (max depth 2)
8. **Use descriptive error tuples** - `{:error, {:reason, details}}`
