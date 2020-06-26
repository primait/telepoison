# Telepoison

Telepoison is a [opentelemetry-instrumented](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/glossary.md#instrumented-library) wrapper around HTTPPoison.

## How it works

Telepoison, when executing an HTTP request to an external service, creates an OpenTelemetry span, injects
the [trace context propagation headers](https://www.w3.org/TR/trace-context/) in the request headers, and
ends the span once the response is received.
It automatically sets some of the [HTTP span attributes](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md) like `http.status`, `http.host` etc,
based on the request and response data.

Telepoison by itself is not particularly useful: it becomes useful when used in conjuction with a "server-side"
opentelemetry-instrumented library, e.g. opentelemetry_plug.
These do the opposite work: they take the trace context information from the request headers,
and they create a [SERVER](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/api.md#spankind) span which becomes the currently active span.

Using the two libraries together, it's possible to propagate trace information across several microservices and
through HTTP "jumps".

## Keep in mind

* The [Erlang opentelemetry SDK](https://github.com/open-telemetry/opentelemetry-erlang) stores
the currently active span in a `pdict`, a per-process dict.
If Telepoison is called from a different process than the one that initially handled the request and created
the "server-side" span, Telepoison won't find a parent span and will create a new root client span,
losing the trace context.
In this case, your only option to correctly propagate the trace context is to manually pass around the parent
span, and pass it to Telepoison when doing the HTTP client request.

## What's missing

* Better default span name (use target hostname / path ?)
* Support for explicit parent span
* Support for user-provided span attributes
* Support for fixed span attributes, either in `Teleposion.setup` or in config
* A lot of other stuff..
