# frozen_string_literal: true

require_relative "../browser"
require "rack"
require "erb"
require "json"

module RubyEventStore
  module Browser
    class App
      def self.for(
        event_store_locator:,
        host: nil,
        path: nil,
        api_url: nil,
        environment: nil,
        related_streams_query: DEFAULT_RELATED_STREAMS_QUERY
      )
        Rack::Builder.new do
          use Rack::Static,
              urls: {
                "/ruby_event_store_browser.js" => "ruby_event_store_browser.js",
                "/bootstrap.js" => "bootstrap.js"
              },
              root: "#{__dir__}/../../../public"
          run App.new(
                event_store_locator: event_store_locator,
                related_streams_query: related_streams_query,
                host: host,
                root_path: path,
                api_url: api_url
              )
        end
      end

      def initialize(event_store_locator:, related_streams_query:, host:, root_path:, api_url:)
        @event_store_locator = event_store_locator
        @related_streams_query = related_streams_query
        @api_url = api_url
        @routing = Routing.from_configuration(host, root_path)
      end

      def call(env)
        router = Router.new(routing)
        router.add_route("GET", "/api/events/:event_id") do |params|
          json Event.new(event_store: event_store, event_id: params.fetch("event_id"))
        end
        router.add_route("GET", "/api/streams/:stream_name") do |params, urls|
          json GetStream.new(
                 stream_name: params.fetch("stream_name"),
                 routing: urls,
                 related_streams_query: related_streams_query
               )
        end
        router.add_route("GET", "/api/streams/:stream_name/relationships/events") do |params, urls|
          json GetEventsFromStream.new(
                 event_store: event_store,
                 routing: urls,
                 stream_name: params.fetch("stream_name"),
                 page: params["page"]
               )
        end
        %w[/ /events/:event_id /streams/:stream_name].each do |starting_route|
          router.add_route("GET", starting_route) do |_, urls|
            erb bootstrap_html, root_path: urls.root_path, settings: settings(urls)
          end
        end
        router.handle(Rack::Request.new(env))
      rescue EventNotFound, Router::NoMatch
        not_found
      end

      private

      attr_reader :event_store_locator, :related_streams_query, :routing, :api_url

      def event_store
        event_store_locator.call
      end

      def bootstrap_html
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>RubyEventStore::Browser</title>
            <meta name="ruby-event-store-browser-settings" content="<%= Rack::Utils.escape_html(JSON.dump(settings)) %>">
          </head>
          <body>
            <script type="text/javascript" src="<%= root_path %>/ruby_event_store_browser.js"></script>
            <script type="text/javascript" src="<%= root_path %>/bootstrap.js"></script>
          </body>
        </html>
        HTML
      end

      def not_found
        [404, {}, []]
      end

      def json(body)
        [200, { "Content-Type" => "application/vnd.api+json" }, [JSON.dump(body.to_h)]]
      end

      def erb(template, **locals)
        [200, { "Content-Type" => "text/html;charset=utf-8" }, [ERB.new(template).result_with_hash(locals)]]
      end

      def settings(routing)
        { rootUrl: routing.root_url, apiUrl: api_url || routing.api_url, resVersion: res_version }
      end

      def res_version
        RubyEventStore::VERSION
      end
    end
  end
end
