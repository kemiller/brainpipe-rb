# Brainpipe Requirements

## Overview

Brainpipe is a Ruby library for composing AI API calls and related tasks into pipelines. It provides a "Rack for AI" abstraction where discrete operations can be chained together with a shared property namespace.

## Core Concepts

### Pipe
A sequence of stages that processes data from input to output.

### Operation
A discrete unit of work (e.g., a BAML function call for LLM/GenAI operations).

### Stage
A grouping of one or more operations with configurable execution semantics.

### Property Namespace
A shared key-value store accessible to all operations within a pipe execution.

---

## Functional Requirements

### FR-1: Pipe

- FR-1.1: A pipe MUST consist of an ordered sequence of stages
- FR-1.2: A pipe MUST be callable via an API entry point
- FR-1.3: A pipe MUST return processed output upon completion
- FR-1.4: A pipe MUST accept a single property set as input (not an array)
- FR-1.5: A pipe MUST return a single property set as output (not an array)
- FR-1.6: A pipe MUST advertise its input properties, inherited from its first stage
- FR-1.7: A pipe MUST advertise its output properties, inherited from its last stage
- FR-1.8: A pipe MUST validate input/output property compatibility at construction time
- FR-1.9: A pipe MUST raise an error on construction if stage property requirements are incompatible
- FR-1.10: A pipe MUST fail fast on operation errors (unless the operation declares it ignores errors)

### FR-2: Operation

- FR-2.1: An operation MUST be implemented as a class or struct
- FR-2.2: An operation MUST declare which properties it reads from the namespace
- FR-2.3: An operation MUST declare which properties it sets in the namespace
- FR-2.4: An operation MUST declare which properties it deletes from the namespace
- FR-2.5: Property declarations MUST be resolvable at the instance level (after initialization with options)
- FR-2.6: An operation MUST define its execution logic
- FR-2.7: An operation MAY declare error handling via boolean or conditional function (does not halt the pipe if ignored)
- FR-2.8: Operations are factories: configured at config load time, they produce executors on demand
- FR-2.9: Each pipe execution MUST receive fresh executor instances from operations
- FR-2.10: In fan-out mode, each parallel branch MUST receive its own executor instance
- FR-2.11: Executors MUST always receive an array of namespaces (even if single element)
- FR-2.12: Executors MUST always return an array of namespaces (same count as input)

### FR-3: Property Namespace

- FR-3.1: The namespace MUST support read, set, and delete operations
- FR-3.2: Properties MUST have associated type expectations when reading or setting
- FR-3.3: The namespace MUST be shared across all operations within a pipe execution
- FR-3.4: Property type compatibility MUST be validated at config load time
- FR-3.5: In fan-out mode, each parallel execution MUST receive an isolated copy of the namespace
- FR-3.6: After fan-out completion, isolated namespaces MUST be collected into an array of property sets

### FR-4: Stage

- FR-4.1: A stage MUST contain one or more operations
- FR-4.2: A stage MUST receive an array of property sets as input
- FR-4.3: A stage MUST support the following execution modes:

#### FR-4.3.1: Merge Mode
- Merge all property sets in the input array (last value wins for conflicts)
- Execute each operation in the stage with the merged property set

#### FR-4.3.2: Fan-Out Mode
- Each property set in the input array is sent to a distinct instance of each operation
- Operations SHOULD execute concurrently (real threads preferred; green threads/async acceptable)

#### FR-4.3.3: Batch Mode
- The entire input array is passed as-is to each operation
- Operations receive the full array and handle iteration internally

#### FR-4.4: Stage Output Contracts
- FR-4.4.1: A stage in merge mode MUST output a single property set
- FR-4.4.2: A stage in fan-out mode MUST output an array of property sets (one per input)
- FR-4.4.3: A stage in batch mode MUST output based on operation's declared output type
- FR-4.4.4: The last stage in a pipe MUST use merge mode to satisfy FR-1.5 (single output)

#### FR-4.5: Parallel Execution
- FR-4.5.1: All operations within a stage MUST execute in parallel
- FR-4.5.2: Sequential operation execution MUST use separate stages
- FR-4.5.3: A stage MUST define a merge strategy for combining parallel operation outputs
- FR-4.5.4: Supported merge strategies: last_in (default), first_in, collate, disjoint

#### FR-4.6: Empty Input
- FR-4.6.1: A stage receiving an empty array MUST raise an error (empty input is invalid)

### FR-5: Configuration

- FR-5.1: Pipes MUST be loadable from YAML configuration files
- FR-5.2: YAML configuration MUST be validated during loading
- FR-5.3: Invalid configuration MUST raise descriptive errors at load time

### FR-6: Observability

- FR-6.1: Each step in a pipe MUST be able to emit debug information on request
- FR-6.2: Debug mode MUST show what each operation is doing during execution
- FR-6.3: A metrics collector MUST be available for gathering execution data (e.g., BAML context)

### FR-7: BAML Integration

- FR-7.1: BAML MUST be a first-class citizen with dedicated support
- FR-7.2: BAML MUST NOT be required; pipes without BAML operations MUST work
- FR-7.3: BAML operations SHOULD integrate with the metrics collector (FR-6.3)
- FR-7.4: BAML operations MUST support raw response access when BAML parsing is insufficient (e.g., image outputs)
- FR-7.5: Raw BAML operations MUST use BAML's Modular API to construct requests and access responses

### FR-10: Image Support

- FR-10.1: The library MUST provide a built-in Image type for representing images
- FR-10.2: The Image type MUST support both URL and base64 representations
- FR-10.3: The Image type MUST support lazy conversion between URL and base64 (fetch on demand)
- FR-10.4: The Image type MUST be convertible to BAML image format for LLM input
- FR-10.5: The Image type MUST support loading from file paths
- FR-10.6: The Image type MUST track MIME type
- FR-10.7: Operations MUST be able to extract images from raw LLM responses (e.g., Gemini's inlineData)

### FR-8: Model Configuration

- FR-8.1: Model configs MUST be named and referenceable by name
- FR-8.2: Model configs MUST specify a provider (e.g., openai, anthropic, vertex, bedrock, azure)
- FR-8.3: Model configs MUST specify a model identifier
- FR-8.4: Model configs MUST support provider-specific options (temperature, max_tokens, api_key, etc.)
- FR-8.5: Model configs MUST be convertible to BAML ClientRegistry format
- FR-8.6: Model configs MUST be definable in YAML configuration files
- FR-8.7: Operations MUST be able to reference model configs by name
- FR-8.9: Model configs MUST support retry configuration (count, backoff) via BAML client options
- FR-8.10: API keys and secrets MUST NOT be stored directly in YAML configuration
- FR-8.11: Model configs MUST support environment variable references (e.g., ${ENV_VAR})
- FR-8.12: Model configs SHOULD support pluggable secret store integration

### FR-9: Timeouts

- FR-9.1: Pipes MAY declare a timeout duration for entire execution
- FR-9.2: Stages MAY declare a timeout duration (applies to stage completion)
- FR-9.3: Operations MAY declare a timeout duration
- FR-9.4: Timeout expiration MUST raise a TimeoutError
- FR-9.5: LLM call timeouts SHOULD be configured via model configs (BAML client level)

---

## Design Principles

- **Tight, focused APIs**: The library is opinionated, not all things to all people
- **Limited scope**: Avoid sprawling workflows; favor composability over configuration
- **Operations as extension point**: Since operations are classes, customization happens there rather than via hooks

---

## Deferred Features

- **Hooks/middleware**: May be needed later, but avoiding for now to keep the API surface small

