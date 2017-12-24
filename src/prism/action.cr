require "http/server"
require "json"
require "./callbacks"

module Prism
  # A callable HTTP action with `Callbacks` included.
  #
  # NOTE: *(From [API](https://crystal-lang.org/api/0.23.1/HTTP/Server/Response.html)) The response #status_code and #headers must be configured before writing the response body. Once response output is written, changing the status and #headers properties has no effect.*
  #
  # ```
  # struct MyAction < Prism::Action
  #   def call
  #     text("ok")
  #   end
  #
  #   after do
  #     p "MyAction: ok"
  #   end
  # end
  #
  # MyAction.call(env)
  # # => "ok"
  # ```
  abstract struct Action
    macro inherited
      include Prism::Callbacks
    end

    abstract def call

    # Initialize and invoke `#call` with `#before`, `#around` and `#after` callbacks.
    def self.call(context : ::HTTP::Server::Context)
      new(context).call_with_callbacks
    end

    # :nodoc:
    def call_with_callbacks
      with_callbacks { call }
    end

    # Will **not** raise on exceed, defaults to 8 MB.
    class_property max_body_size = UInt64.new(8 * 1024 ** 2)

    @body : String?

    # Lazy string version of request body (read *max_body_size* bytes on the first call).
    #
    # ```
    # # Action A
    # def call
    #   body                 # => "foo"
    #   context.request.body # => nil
    # end
    #
    # # Action B
    # def call
    #   context.request.body # => Not nil
    # end
    # ```
    def body
      @body ||= context.request.body.try &.gets(limit: self.class.max_body_size)
    end

    # Current context.
    getter context : ::HTTP::Server::Context

    # :nodoc:
    def initialize(@context : ::HTTP::Server::Context)
    end

    # Set HTTP *status*, close the response and **stop** the execution.
    # Optionally specify *response*, otherwise print a default HTTP response for this *status*.
    #
    # ```
    # def call
    #   halt!(403) # Will print "Unauthorized" into the response body
    #   text("ok") # This line will not be called
    # end
    #
    # def call
    #   halt!(500, "Something's wrong!") # Will print "Something's wrong!" into the response body
    # end
    #
    # def call
    #   halt!(409, {error: "Oops"}) # Will print "Oops" and set content type to JSON
    # end
    #
    # def call
    #   halt!(403, PaymentError) # Will call #to_json on PaymentError
    # end
    # ```
    macro halt!(status, response = nil)
      status({{status.id}})

      {% if response.is_a?(StringLiteral) %}
        text({{response}})
      {% elsif response.is_a?(NilLiteral) %}
        text(HTTP.default_status_message_for({{status.id}}))
      {% else %}
        json({{response}})
      {% end %}

      return false
    end

    # Set HTTP status code.
    #
    # ```
    # def call
    #   status(400)
    # end
    # ```
    def status(new_status value)
      context.response.status_code = value
    end

    private CONTENT_TYPE_TEXT = "text/html; charset=utf-8"

    {% begin %}
      # Write text into the response body.
      # "Content-Type" header is set to `"{{CONTENT_TYPE_TEXT}}"`.
      #
      # ```
      # def call
      #   text("ok")
      # end
      # ```
      def text(value)
        context.response.content_type = CONTENT_TYPE_TEXT
        context.response.print(value)
      end
    {% end %}

    private CONTENT_TYPE_JSON = "application/json; charset=utf-8"

    {% begin %}
      # Cast *value* to JSON and write it into the response body.
      # "Content-Type" header is set to `"{{CONTENT_TYPE_JSON}}"`.
      #
      # ```
      # def call
      #   json(object)
      # end
      # ```
      def json(value)
        context.response.content_type = CONTENT_TYPE_JSON
        context.response.print(value.to_json)
      end
    {% end %}
  end
end

require "./action/*"
