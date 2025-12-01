# Rails Integration Design

## Overview

Integrate Brainpipe into Rails applications via Railties with:
1. Automatic configuration and loading
2. Mountable engine with API endpoints for running pipelines
3. Flexible routing (explicit routes per pipeline or catch-all)

## File Structure

```
lib/brainpipe/
  rails/
    railtie.rb              # Rails integration hooks
    engine.rb               # Mountable Rails engine
    configuration.rb        # Rails-specific config extensions
    controller.rb           # API controller for pipelines
    routes.rb               # Route DSL helpers
```

---

## 1. Railtie (`lib/brainpipe/rails/railtie.rb`)

Hooks into Rails lifecycle for automatic setup.

```ruby
module Brainpipe
  module Rails
    class Railtie < ::Rails::Railtie
      config.brainpipe = ActiveSupport::OrderedOptions.new

      # Defaults
      config.brainpipe.config_path = nil          # Auto-detect
      config.brainpipe.autoload_paths = []        # Additional paths
      config.brainpipe.debug = false
      config.brainpipe.catch_all_routes = false   # Enable /pipelines/:name
      config.brainpipe.api_authentication = nil   # Proc for auth
      config.brainpipe.before_execute = nil       # Proc hook
      config.brainpipe.after_execute = nil        # Proc hook
      config.brainpipe.expose_pipes = :all        # :all, :none, or Array of names

      initializer "brainpipe.configure" do |app|
        # Set config_path from Rails conventions
        Brainpipe.configure do |config|
          rails_config = app.config.brainpipe

          config.config_path = rails_config.config_path ||
                               ::Rails.root.join("config/brainpipe")

          config.debug = rails_config.debug || ::Rails.env.development?

          # Auto-add conventional paths
          config.autoload_path ::Rails.root.join("app/operations")
          config.autoload_path ::Rails.root.join("app/pipelines")

          rails_config.autoload_paths.each do |path|
            config.autoload_path path
          end
        end
      end

      initializer "brainpipe.load", after: "brainpipe.configure" do
        # Load on first request in development, immediately otherwise
        if ::Rails.env.development?
          ActiveSupport::Reloader.to_prepare { Brainpipe.load! }
        else
          Brainpipe.load!
        end
      end

      initializer "brainpipe.log_subscriber" do
        Brainpipe::Rails::LogSubscriber.attach_to :brainpipe
      end
    end
  end
end
```

---

## 2. Engine (`lib/brainpipe/rails/engine.rb`)

Mountable engine for the pipeline API.

```ruby
module Brainpipe
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Brainpipe::Rails

      # Routes defined in engine
      # Mount with: mount Brainpipe::Rails::Engine => "/brainpipe"
    end
  end
end
```

**Engine Routes (`config/routes.rb` in engine):**

```ruby
Brainpipe::Rails::Engine.routes.draw do
  # Health check
  get "health", to: "pipelines#health"

  # List available pipelines
  get "pipelines", to: "pipelines#index"

  # Pipeline schema/info
  get "pipelines/:name", to: "pipelines#show"

  # Execute pipeline (catch-all when enabled)
  post "pipelines/:name", to: "pipelines#execute"
end
```

---

## 3. Controller (`lib/brainpipe/rails/pipelines_controller.rb`)

```ruby
module Brainpipe
  module Rails
    class PipelinesController < ActionController::API
      before_action :authenticate!, if: -> { authentication_configured? }
      before_action :set_pipe, only: [:show, :execute]
      before_action :check_pipe_exposed, only: [:show, :execute]

      # GET /health
      def health
        render json: {
          status: "ok",
          loaded: Brainpipe.loaded?,
          version: Brainpipe::VERSION
        }
      end

      # GET /pipelines
      def index
        pipes = exposed_pipe_names.map do |name|
          pipe = Brainpipe.pipe(name)
          {
            name: name,
            input_schema: pipe.input_schema,
            output_schema: pipe.output_schema
          }
        end
        render json: { pipelines: pipes }
      end

      # GET /pipelines/:name
      def show
        render json: {
          name: @pipe_name,
          input_schema: @pipe.input_schema,
          output_schema: @pipe.output_schema,
          stages: @pipe.stages.map(&:name)
        }
      end

      # POST /pipelines/:name
      def execute
        input = parse_input

        run_before_hook(input)

        result = @pipe.call(input)

        run_after_hook(result)

        render json: {
          success: true,
          result: result.to_h
        }
      rescue Brainpipe::ContractViolationError => e
        render json: { success: false, error: e.message, type: "contract_violation" }, status: 422
      rescue Brainpipe::ExecutionError => e
        render json: { success: false, error: e.message, type: "execution_error" }, status: 500
      rescue Brainpipe::TimeoutError => e
        render json: { success: false, error: e.message, type: "timeout" }, status: 504
      end

      private

      def set_pipe
        @pipe_name = params[:name].to_sym
        @pipe = Brainpipe.pipe(@pipe_name)
      rescue Brainpipe::MissingPipeError
        render json: { error: "Pipeline not found: #{params[:name]}" }, status: 404
      end

      def check_pipe_exposed
        unless pipe_exposed?(@pipe_name)
          render json: { error: "Pipeline not accessible" }, status: 403
        end
      end

      def parse_input
        case request.content_type
        when /json/
          params.permit!.to_h.except(:name, :controller, :action)
        when /form/
          params.permit!.to_h.except(:name, :controller, :action)
        else
          request.body.read.then { |b| JSON.parse(b, symbolize_names: true) }
        end
      end

      def exposed_pipe_names
        case rails_config.expose_pipes
        when :all
          Brainpipe.pipe_names
        when :none
          []
        when Array
          rails_config.expose_pipes
        else
          []
        end
      end

      def pipe_exposed?(name)
        case rails_config.expose_pipes
        when :all then true
        when :none then false
        when Array then rails_config.expose_pipes.include?(name)
        else false
        end
      end

      def authentication_configured?
        rails_config.api_authentication.present?
      end

      def authenticate!
        unless rails_config.api_authentication.call(request)
          render json: { error: "Unauthorized" }, status: 401
        end
      end

      def run_before_hook(input)
        rails_config.before_execute&.call(@pipe_name, input, request)
      end

      def run_after_hook(result)
        rails_config.after_execute&.call(@pipe_name, result, request)
      end

      def rails_config
        ::Rails.application.config.brainpipe
      end
    end
  end
end
```

---

## 4. Route DSL Helpers (`lib/brainpipe/rails/routes.rb`)

Extend Rails routing DSL for convenient pipe exposure.

```ruby
module Brainpipe
  module Rails
    module Routes
      # Usage in config/routes.rb:
      #
      #   brainpipe_pipes                           # Mount all pipes at /pipelines/:name
      #   brainpipe_pipes path: "/api/v1/ai"        # Custom base path
      #   brainpipe_pipes only: [:summarize, :chat] # Specific pipes only
      #   brainpipe_pipe :summarize                 # Single pipe at /summarize
      #   brainpipe_pipe :summarize, path: "/ai/summarize"
      #
      def brainpipe_pipes(path: "/pipelines", only: nil, except: nil)
        scope path do
          get "/", to: "brainpipe/rails/pipelines#index"
          get "/:name", to: "brainpipe/rails/pipelines#show", constraints: pipe_constraint(only, except)
          post "/:name", to: "brainpipe/rails/pipelines#execute", constraints: pipe_constraint(only, except)
        end
      end

      def brainpipe_pipe(name, path: nil, as: nil)
        route_path = path || "/#{name}"
        route_name = as || "brainpipe_#{name}"

        get route_path, to: "brainpipe/rails/pipelines#show",
            defaults: { name: name.to_s }, as: "#{route_name}_info"
        post route_path, to: "brainpipe/rails/pipelines#execute",
            defaults: { name: name.to_s }, as: route_name
      end

      def brainpipe_health(path: "/brainpipe/health")
        get path, to: "brainpipe/rails/pipelines#health"
      end

      private

      def pipe_constraint(only, except)
        return {} if only.nil? && except.nil?

        lambda do |request|
          name = request.params[:name]&.to_sym
          return false if only && !only.include?(name)
          return false if except && except.include?(name)
          true
        end
      end
    end
  end
end

# Extend ActionDispatch::Routing::Mapper
ActionDispatch::Routing::Mapper.include(Brainpipe::Rails::Routes)
```

---

## 5. Log Subscriber (`lib/brainpipe/rails/log_subscriber.rb`)

Integration with Rails logging.

```ruby
module Brainpipe
  module Rails
    class LogSubscriber < ActiveSupport::LogSubscriber
      def pipe_started(event)
        info "  Brainpipe: #{event.payload[:pipe]} started"
      end

      def pipe_completed(event)
        info "  Brainpipe: #{event.payload[:pipe]} completed in #{event.duration.round(1)}ms"
      end

      def pipe_failed(event)
        error "  Brainpipe: #{event.payload[:pipe]} failed - #{event.payload[:error]}"
      end

      def operation_completed(event)
        debug "    -> #{event.payload[:operation]} (#{event.duration.round(1)}ms)"
      end
    end
  end
end
```

---

## 6. Rails Generator (optional)

```ruby
# lib/generators/brainpipe/install_generator.rb
module Brainpipe
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "brainpipe.rb", "config/initializers/brainpipe.rb"
      end

      def create_config_directory
        empty_directory "config/brainpipe"
        template "models.yml", "config/brainpipe/models.yml"
      end

      def create_operations_directory
        empty_directory "app/operations"
        template "example_operation.rb", "app/operations/example_operation.rb"
      end

      def add_routes
        route 'mount Brainpipe::Rails::Engine => "/brainpipe"'
      end
    end
  end
end
```

**Template: `config/initializers/brainpipe.rb`**

```ruby
Rails.application.config.brainpipe.tap do |config|
  # Path to pipe configuration YAML files (default: config/brainpipe)
  # config.config_path = Rails.root.join("config/brainpipe")

  # Enable debug output in all environments (default: development only)
  # config.debug = Rails.env.development?

  # Additional paths to autoload operations from
  # config.autoload_paths = [Rails.root.join("lib/operations")]

  # Which pipes to expose via API
  # :all       - All loaded pipes (default)
  # :none      - No pipes (disable API)
  # [:a, :b]   - Only specific pipes
  # config.expose_pipes = :all

  # API authentication (receives request, return truthy for authenticated)
  # config.api_authentication = ->(request) {
  #   request.headers["X-API-Key"] == Rails.application.credentials.brainpipe_api_key
  # }

  # Before/after hooks for pipeline execution
  # config.before_execute = ->(pipe_name, input, request) {
  #   Rails.logger.info "Executing #{pipe_name} with #{input.keys}"
  # }
  # config.after_execute = ->(pipe_name, result, request) {
  #   # Track metrics, audit log, etc.
  # }
end
```

---

## Usage Examples

### Basic Setup

```ruby
# Gemfile
gem "brainpipe"

# config/routes.rb
Rails.application.routes.draw do
  mount Brainpipe::Rails::Engine => "/brainpipe"
end
```

Access:
- `GET /brainpipe/health` - Health check
- `GET /brainpipe/pipelines` - List all pipes
- `GET /brainpipe/pipelines/summarize` - Pipe schema
- `POST /brainpipe/pipelines/summarize` - Execute pipe

### Custom Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Mount specific pipes at custom paths
  brainpipe_pipe :summarize, path: "/api/v1/summarize"
  brainpipe_pipe :chat, path: "/api/v1/chat"

  # Or mount all pipes at a path
  brainpipe_pipes path: "/api/v1/ai", only: [:summarize, :chat, :extract]

  # Health check
  brainpipe_health path: "/health/ai"
end
```

### With Authentication

```ruby
# config/initializers/brainpipe.rb
Rails.application.config.brainpipe.api_authentication = ->(request) {
  token = request.headers["Authorization"]&.remove("Bearer ")
  ApiKey.active.exists?(token: token)
}
```

### With Hooks for Auditing

```ruby
Rails.application.config.brainpipe.before_execute = ->(pipe_name, input, request) {
  PipelineAudit.create!(
    pipe: pipe_name,
    input_keys: input.keys,
    user: request.env["warden"].user,
    started_at: Time.current
  )
}

Rails.application.config.brainpipe.after_execute = ->(pipe_name, result, request) {
  PipelineAudit.where(pipe: pipe_name).last&.update!(
    completed_at: Time.current,
    output_keys: result.to_h.keys
  )
}
```

### Selective Pipe Exposure

```ruby
# Only expose specific pipes
Rails.application.config.brainpipe.expose_pipes = [:summarize, :extract]

# Or disable API entirely (use programmatically only)
Rails.application.config.brainpipe.expose_pipes = :none
```

---

## API Response Formats

### Health Check
```json
GET /brainpipe/health

{
  "status": "ok",
  "loaded": true,
  "version": "0.1.0"
}
```

### List Pipelines
```json
GET /brainpipe/pipelines

{
  "pipelines": [
    {
      "name": "summarize",
      "input_schema": { "text": "String" },
      "output_schema": { "summary": "String" }
    }
  ]
}
```

### Pipeline Info
```json
GET /brainpipe/pipelines/summarize

{
  "name": "summarize",
  "input_schema": { "text": "String" },
  "output_schema": { "summary": "String" },
  "stages": ["extract", "summarize", "format"]
}
```

### Execute Pipeline
```json
POST /brainpipe/pipelines/summarize
Content-Type: application/json

{ "text": "Long document content..." }

// Success
{
  "success": true,
  "result": {
    "summary": "Brief summary..."
  }
}

// Error
{
  "success": false,
  "error": "Property 'text' expected String, got NilClass",
  "type": "contract_violation"
}
```

---

## Implementation Order

1. **Railtie** - Core Rails integration
2. **Engine** - Mountable routes
3. **Controller** - API endpoints
4. **Routes DSL** - Custom routing helpers
5. **Log Subscriber** - Rails logging integration
6. **Generator** - `rails g brainpipe:install`

---

## 7. Streaming Responses (`lib/brainpipe/rails/streaming.rb`)

Support Server-Sent Events (SSE) for long-running pipelines with stage-by-stage progress.

### Controller Addition

```ruby
module Brainpipe
  module Rails
    class PipelinesController < ActionController::API
      include ActionController::Live

      # POST /pipelines/:name/stream
      def stream
        input = parse_input

        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        run_before_hook(input)

        streaming_collector = StreamingCollector.new(response.stream)

        result = @pipe.call(input, metrics_collector: streaming_collector)

        streaming_collector.send_complete(result.to_h)

        run_after_hook(result)
      rescue Brainpipe::ContractViolationError => e
        streaming_collector&.send_error("contract_violation", e.message)
      rescue Brainpipe::ExecutionError => e
        streaming_collector&.send_error("execution_error", e.message)
      rescue Brainpipe::TimeoutError => e
        streaming_collector&.send_error("timeout", e.message)
      ensure
        response.stream.close
      end
    end
  end
end
```

### Streaming Collector

```ruby
module Brainpipe
  module Rails
    class StreamingCollector < Brainpipe::Observability::MetricsCollector
      def initialize(stream)
        @stream = stream
      end

      def pipe_started(pipe:, input:)
        send_event("pipe_started", { pipe: pipe, input_keys: input.keys })
      end

      def stage_started(stage:, pipe:, namespace_count:)
        send_event("stage_started", { stage: stage, namespace_count: namespace_count })
      end

      def stage_completed(stage:, pipe:, duration_ms:, namespace_count:)
        send_event("stage_completed", {
          stage: stage,
          duration_ms: duration_ms,
          namespace_count: namespace_count
        })
      end

      def operation_started(operation_class:, stage:, pipe:)
        send_event("operation_started", { operation: operation_class.name })
      end

      def operation_completed(operation_class:, namespace:, duration_ms:, stage:, pipe:)
        send_event("operation_completed", {
          operation: operation_class.name,
          duration_ms: duration_ms
        })
      end

      def operation_failed(operation_class:, error:, stage:, pipe:)
        send_event("operation_failed", {
          operation: operation_class.name,
          error: error.message
        })
      end

      def send_complete(result)
        send_event("complete", { result: result })
      end

      def send_error(type, message)
        send_event("error", { type: type, message: message })
      end

      private

      def send_event(event, data)
        @stream.write("event: #{event}\n")
        @stream.write("data: #{data.to_json}\n\n")
      rescue IOError
        # Client disconnected
      end
    end
  end
end
```

### Engine Routes Update

```ruby
Brainpipe::Rails::Engine.routes.draw do
  # ... existing routes ...

  # Streaming execution
  post "pipelines/:name/stream", to: "pipelines#stream"
end
```

### Route DSL Update

```ruby
def brainpipe_pipe(name, path: nil, as: nil, stream: false)
  route_path = path || "/#{name}"
  route_name = as || "brainpipe_#{name}"

  get route_path, to: "brainpipe/rails/pipelines#show",
      defaults: { name: name.to_s }, as: "#{route_name}_info"
  post route_path, to: "brainpipe/rails/pipelines#execute",
      defaults: { name: name.to_s }, as: route_name

  if stream
    post "#{route_path}/stream", to: "brainpipe/rails/pipelines#stream",
        defaults: { name: name.to_s }, as: "#{route_name}_stream"
  end
end

def brainpipe_pipes(path: "/pipelines", only: nil, except: nil, stream: false)
  scope path do
    get "/", to: "brainpipe/rails/pipelines#index"
    get "/:name", to: "brainpipe/rails/pipelines#show", constraints: pipe_constraint(only, except)
    post "/:name", to: "brainpipe/rails/pipelines#execute", constraints: pipe_constraint(only, except)

    if stream
      post "/:name/stream", to: "brainpipe/rails/pipelines#stream", constraints: pipe_constraint(only, except)
    end
  end
end
```

### Client Usage (JavaScript)

```javascript
const eventSource = new EventSource('/brainpipe/pipelines/summarize/stream', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ text: 'Long document...' })
});

// Note: EventSource doesn't support POST, use fetch with ReadableStream instead:
async function streamPipeline(name, input) {
  const response = await fetch(`/brainpipe/pipelines/${name}/stream`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input)
  });

  const reader = response.body.getReader();
  const decoder = new TextDecoder();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const text = decoder.decode(value);
    const lines = text.split('\n');

    for (const line of lines) {
      if (line.startsWith('event: ')) {
        const event = line.slice(7);
        // Handle event type
      } else if (line.startsWith('data: ')) {
        const data = JSON.parse(line.slice(6));
        console.log('Progress:', data);
      }
    }
  }
}
```

### SSE Event Format

```
event: pipe_started
data: {"pipe":"summarize","input_keys":["text"]}

event: stage_started
data: {"stage":"extract","namespace_count":1}

event: operation_started
data: {"operation":"ExtractKeyPoints"}

event: operation_completed
data: {"operation":"ExtractKeyPoints","duration_ms":1523}

event: stage_completed
data: {"stage":"extract","duration_ms":1530,"namespace_count":1}

event: complete
data: {"result":{"summary":"Brief summary of the document..."}}
```

---

## 8. Background Execution with ActiveJob (`lib/brainpipe/rails/job.rb`)

Execute pipelines asynchronously with status tracking and webhook callbacks.

### Pipeline Job

```ruby
module Brainpipe
  module Rails
    class PipelineJob < ApplicationJob
      queue_as :brainpipe

      def perform(execution_id, pipe_name, input, options = {})
        execution = find_or_create_execution(execution_id, pipe_name)
        execution.update!(status: :running, started_at: Time.current)

        pipe = Brainpipe.pipe(pipe_name.to_sym)
        result = pipe.call(input.symbolize_keys)

        execution.update!(
          status: :completed,
          completed_at: Time.current,
          result: result.to_h
        )

        notify_webhook(options[:webhook_url], execution) if options[:webhook_url]

      rescue StandardError => e
        execution&.update!(
          status: :failed,
          completed_at: Time.current,
          error: { type: e.class.name, message: e.message }
        )

        notify_webhook(options[:webhook_url], execution) if options[:webhook_url]

        raise # Re-raise for ActiveJob retry handling
      end

      private

      def find_or_create_execution(id, pipe_name)
        if defined?(Brainpipe::Rails::Execution)
          Brainpipe::Rails::Execution.find_or_create_by!(id: id) do |e|
            e.pipe_name = pipe_name
            e.status = :pending
          end
        else
          OpenStruct.new(
            id: id,
            update!: ->(attrs) { attrs.each { |k, v| self[k] = v } }
          )
        end
      end

      def notify_webhook(url, execution)
        return unless url.present?

        payload = {
          execution_id: execution.id,
          pipe_name: execution.pipe_name,
          status: execution.status,
          result: execution.result,
          error: execution.error,
          started_at: execution.started_at,
          completed_at: execution.completed_at
        }

        Net::HTTP.post(
          URI(url),
          payload.to_json,
          "Content-Type" => "application/json"
        )
      rescue StandardError => e
        ::Rails.logger.error "Brainpipe webhook failed: #{e.message}"
      end
    end
  end
end
```

### Execution Model (Optional ActiveRecord)

```ruby
# Migration
class CreateBrainpipeExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :brainpipe_executions, id: :uuid do |t|
      t.string :pipe_name, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :input, default: {}
      t.jsonb :result, default: {}
      t.jsonb :error, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index :status
      t.index :pipe_name
      t.index :created_at
    end
  end
end

# Model
module Brainpipe
  module Rails
    class Execution < ApplicationRecord
      self.table_name = "brainpipe_executions"

      enum status: {
        pending: "pending",
        running: "running",
        completed: "completed",
        failed: "failed"
      }

      validates :pipe_name, presence: true
    end
  end
end
```

### Controller Additions

```ruby
module Brainpipe
  module Rails
    class PipelinesController < ActionController::API
      # POST /pipelines/:name/async
      def execute_async
        input = parse_input
        execution_id = SecureRandom.uuid

        run_before_hook(input)

        options = {
          webhook_url: params[:webhook_url]
        }

        # Store input if using ActiveRecord tracking
        if defined?(Execution)
          Execution.create!(
            id: execution_id,
            pipe_name: @pipe_name,
            status: :pending,
            input: input
          )
        end

        PipelineJob.perform_later(execution_id, @pipe_name.to_s, input, options)

        render json: {
          execution_id: execution_id,
          status: "pending",
          status_url: pipeline_execution_url(@pipe_name, execution_id),
          webhook_url: params[:webhook_url]
        }, status: 202
      end

      # GET /pipelines/:name/executions/:id
      def execution_status
        execution_id = params[:id]

        if defined?(Execution)
          execution = Execution.find(execution_id)
          render json: {
            execution_id: execution.id,
            pipe_name: execution.pipe_name,
            status: execution.status,
            result: execution.completed? ? execution.result : nil,
            error: execution.failed? ? execution.error : nil,
            started_at: execution.started_at,
            completed_at: execution.completed_at
          }
        else
          render json: { error: "Execution tracking not configured" }, status: 501
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Execution not found" }, status: 404
      end
    end
  end
end
```

### Engine Routes Update

```ruby
Brainpipe::Rails::Engine.routes.draw do
  # ... existing routes ...

  # Async execution
  post "pipelines/:name/async", to: "pipelines#execute_async"
  get "pipelines/:name/executions/:id", to: "pipelines#execution_status"
end
```

### Route DSL Update

```ruby
def brainpipe_pipe(name, path: nil, as: nil, stream: false, async: false)
  route_path = path || "/#{name}"
  route_name = as || "brainpipe_#{name}"

  get route_path, to: "brainpipe/rails/pipelines#show",
      defaults: { name: name.to_s }, as: "#{route_name}_info"
  post route_path, to: "brainpipe/rails/pipelines#execute",
      defaults: { name: name.to_s }, as: route_name

  if stream
    post "#{route_path}/stream", to: "brainpipe/rails/pipelines#stream",
        defaults: { name: name.to_s }, as: "#{route_name}_stream"
  end

  if async
    post "#{route_path}/async", to: "brainpipe/rails/pipelines#execute_async",
        defaults: { name: name.to_s }, as: "#{route_name}_async"
    get "#{route_path}/executions/:id", to: "brainpipe/rails/pipelines#execution_status",
        defaults: { name: name.to_s }, as: "#{route_name}_execution"
  end
end
```

### Railtie Configuration Additions

```ruby
config.brainpipe.async_queue = :brainpipe           # ActiveJob queue name
config.brainpipe.execution_retention = 7.days       # How long to keep execution records
config.brainpipe.track_executions = true            # Use ActiveRecord tracking
```

### Usage Examples

#### Async with Polling

```ruby
# Client request
POST /brainpipe/pipelines/summarize/async
Content-Type: application/json

{ "text": "Long document..." }

# Response (202 Accepted)
{
  "execution_id": "abc-123-def",
  "status": "pending",
  "status_url": "/brainpipe/pipelines/summarize/executions/abc-123-def"
}

# Poll for status
GET /brainpipe/pipelines/summarize/executions/abc-123-def

# Response (running)
{
  "execution_id": "abc-123-def",
  "pipe_name": "summarize",
  "status": "running",
  "started_at": "2024-01-15T10:30:00Z"
}

# Response (completed)
{
  "execution_id": "abc-123-def",
  "pipe_name": "summarize",
  "status": "completed",
  "result": { "summary": "Brief summary..." },
  "started_at": "2024-01-15T10:30:00Z",
  "completed_at": "2024-01-15T10:30:05Z"
}
```

#### Async with Webhook

```ruby
POST /brainpipe/pipelines/summarize/async
Content-Type: application/json

{
  "text": "Long document...",
  "webhook_url": "https://myapp.com/webhooks/brainpipe"
}

# Webhook callback when complete
POST https://myapp.com/webhooks/brainpipe
Content-Type: application/json

{
  "execution_id": "abc-123-def",
  "pipe_name": "summarize",
  "status": "completed",
  "result": { "summary": "Brief summary..." },
  "started_at": "2024-01-15T10:30:00Z",
  "completed_at": "2024-01-15T10:30:05Z"
}
```

### Generator Update

```ruby
# lib/generators/brainpipe/install_generator.rb
class_option :async, type: :boolean, default: false,
  desc: "Generate migration for async execution tracking"

def create_migration
  return unless options[:async]

  migration_template "create_brainpipe_executions.rb",
    "db/migrate/create_brainpipe_executions.rb"
end
```

---

## Updated File Structure

```
lib/brainpipe/
  rails/
    railtie.rb              # Rails integration hooks
    engine.rb               # Mountable Rails engine
    configuration.rb        # Rails-specific config extensions
    pipelines_controller.rb # API controller for pipelines
    routes.rb               # Route DSL helpers
    log_subscriber.rb       # Rails logging integration
    streaming_collector.rb  # SSE streaming support
    pipeline_job.rb         # ActiveJob for async execution
    execution.rb            # Optional ActiveRecord model
lib/generators/
  brainpipe/
    install_generator.rb
    templates/
      brainpipe.rb
      models.yml
      create_brainpipe_executions.rb
```

---

## Updated Implementation Order

1. **Railtie** - Core Rails integration
2. **Engine** - Mountable routes
3. **Controller** - Basic API endpoints (health, index, show, execute)
4. **Routes DSL** - Custom routing helpers
5. **Log Subscriber** - Rails logging integration
6. **Streaming** - SSE support for long-running pipes
7. **ActiveJob** - Async execution with status tracking
8. **Generator** - `rails g brainpipe:install [--async]`
