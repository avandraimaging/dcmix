# Contributing to Dcmix

Thank you for your interest in contributing to Dcmix! This document provides guidelines and information for contributors.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building something together.

## Getting Started

### Prerequisites

- Elixir 1.18 or later
- Erlang/OTP 27 or later
- Git

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/dcmix.git
   cd dcmix
   ```
3. Install dependencies:
   ```bash
   mix deps.get
   ```
4. Run tests to verify setup:
   ```bash
   mix test
   ```

## Development Workflow

### Running Tests

```bash
# Run all tests
mix test

# Run tests with coverage (minimum 90% required)
mix test --cover

# Run a specific test file
mix test test/dcmix_test.exs
```

### Code Quality

We use automated tools to maintain code quality:

```bash
# Run static analysis
mix credo --strict

# Run security analysis
mix sobelow

# Format code
mix format
```

All of these checks run in CI and must pass before merging.

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test additions or changes
- `refactor:` - Code refactoring
- `ci:` - CI/CD changes

Examples:
```
feat: add support for JPEG 2000 decompression
fix: handle malformed private creator tags
docs: add examples for pixel data manipulation
```

## Pull Request Process

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```

2. **Make your changes** following the coding standards below

3. **Write tests** for new functionality (maintain 90%+ coverage)

4. **Run the full test suite** and quality checks:
   ```bash
   mix test --cover
   mix credo --strict
   mix sobelow
   mix format --check-formatted
   ```

5. **Push your branch** and open a PR against `main`

6. **Request review** from a code owner - PRs require approval from an Avandra team member

## Coding Standards

### General Guidelines

- Write clear, self-documenting code
- Keep functions small and focused
- Use pattern matching over conditionals where appropriate
- Handle errors explicitly with `{:ok, result}` / `{:error, reason}` tuples

### Documentation

- Add `@moduledoc` to all modules
- Add `@doc` to public functions
- Include examples in documentation where helpful
- Use typespecs (`@spec`) for public functions

### Testing

- Write tests for all new functionality
- Include both happy path and error cases
- Use descriptive test names
- Keep test data minimal but representative

### DICOM-Specific

- Follow DICOM standard terminology and conventions
- Reference PS3.x section numbers in comments for complex logic
- Use standard DICOM tag keywords where available
- Preserve data integrity - never silently drop or modify elements

## Architecture Overview

```
lib/dcmix/
├── dcmix.ex           # Main public API
├── data_element.ex    # DICOM data element struct
├── data_set.ex        # DICOM dataset operations
├── tag.ex             # Tag handling utilities
├── vr.ex              # Value representation handling
├── dictionary.ex      # DICOM data dictionary
├── parser/            # File parsing modules
├── writer/            # File writing modules
├── export/            # Export formats (JSON, XML, image)
├── import/            # Import formats (JSON, XML, image)
├── pixel_data.ex      # Pixel data operations
└── private_tag.ex     # Private tag support
```

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
