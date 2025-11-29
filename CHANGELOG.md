# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024

### Added

- Core pipeline framework with `Pipe`, `Stage`, and `Operation` classes
- Immutable `Namespace` class for type-safe property handling
- Type system with support for:
  - Basic types: `String`, `Integer`, `Float`, `Symbol`, `Boolean`
  - Collection types: Arrays (`[String]`), Hashes (`{ String => Integer }`)
  - Object structures: `{ name: String, age: Integer }`
  - Special types: `Any`, `Optional[T]`, `Enum[*values]`, `Union[*types]`
- `TypeChecker` for runtime type validation with detailed error paths
- Stage execution modes:
  - `:merge` - Combine namespaces and run operations
  - `:fan_out` - Parallel execution per namespace
  - `:batch` - Process entire namespace array
- Merge strategies for parallel operations:
  - `:last_in` - Last to complete wins
  - `:first_in` - First to complete wins
  - `:collate` - Conflicts become arrays
  - `:disjoint` - Error on overlap
- Contract validation in `Executor`:
  - Read validation (property existence and type)
  - Set validation (declared outputs appear)
  - Delete validation (declared deletions removed)
  - Output count validation
- Built-in operations:
  - `Transform` - Rename/copy properties with type preservation
  - `Filter` - Conditional namespace filtering
  - `Merge` - Combine multiple properties
  - `Log` - Debug logging
  - `Baml` - BAML function integration
- Configuration DSL:
  - Model definition with provider, capabilities, and options
  - Operation registration
  - Autoload paths
  - Secret resolution
  - Thread pool configuration
- YAML-based pipeline configuration via `Loader`
- Observability:
  - Debug mode with formatted output
  - `MetricsCollector` interface for custom metrics
  - Callbacks for operation/stage/pipe lifecycle events
- Timeout support at pipe, stage, and operation levels
- Error handling:
  - Per-operation error handlers (`ignore_errors`)
  - Comprehensive error hierarchy
  - Detailed error messages with context
- BAML integration:
  - Dynamic schema introspection
  - Input/output field mapping
  - Client registry support
  - Graceful degradation when BAML not installed

### Dependencies

- `concurrent-ruby ~> 1.2` for thread pool execution
- `zeitwerk ~> 2.6` for autoloading
- `baml` (optional) for LLM function integration
