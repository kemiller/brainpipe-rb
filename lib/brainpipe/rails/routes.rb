module Brainpipe
  module Rails
    module Routes
      def brainpipe_pipes(path: "/pipelines", only: nil, except: nil, stream: false, async: false)
        scope path do
          get "/", to: "brainpipe/rails/pipelines#index"
          get "/:name", to: "brainpipe/rails/pipelines#show", constraints: pipe_constraint(only, except)
          post "/:name", to: "brainpipe/rails/pipelines#execute", constraints: pipe_constraint(only, except)

          if stream
            post "/:name/stream", to: "brainpipe/rails/pipelines#stream", constraints: pipe_constraint(only, except)
          end

          if async
            post "/:name/async", to: "brainpipe/rails/pipelines#execute_async", constraints: pipe_constraint(only, except)
            get "/:name/executions/:id", to: "brainpipe/rails/pipelines#execution_status", constraints: pipe_constraint(only, except)
          end
        end
      end

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

      def brainpipe_health(path: "/brainpipe/health")
        get path, to: "brainpipe/rails/pipelines#health"
      end

      private

      def pipe_constraint(only, except)
        return {} if only.nil? && except.nil?

        lambda do |request|
          name = request.params[:name]&.to_sym
          return false if only && !only.map(&:to_sym).include?(name)
          return false if except && except.map(&:to_sym).include?(name)
          true
        end
      end
    end
  end
end

ActionDispatch::Routing::Mapper.include(Brainpipe::Rails::Routes) if defined?(ActionDispatch::Routing::Mapper)
