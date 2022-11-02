# Telepoison

[![Module Version](https://img.shields.io/hexpm/v/telepoison.svg)](https://hex.pm/packages/telepoison)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/telepoison/)
[![Total Download](https://img.shields.io/hexpm/dt/telepoison.svg)](https://hex.pm/packages/telepoison)
[![License](https://img.shields.io/hexpm/l/telepoison.svg)](https://github.com/primait/telepoison/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/primait/telepoison.svg)](https://github.com/primait/telepoison/commits/master)

Telepoison is a [opentelemetry-instrumented](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/glossary.md#instrumented-library) wrapper around HTTPoison.

## Usage

Simply replace `HTTPoison` with `Telepoison` when calling one of the request methods (get(), get!(), post(), request(), etc.)

```elixir
# before
HTTPoison.get!(url, headers, opts)

# after
Telepoison.get!(url, headers, opts)
```

Additionally, telepoison adds some options that can be passed in the `opts` HTTPoison argument to set OpenTelemetry-related stuff.
These typically start with `:ot_`

* `:ot_span_name` sets the span name
* `:ot_attributes` additional span attributes that will be added to the span. Should be a list of {name, value} tuples.
* `:resource_route` sets the `http.route` attribute explicitly. This can be inferred automatically by passing in `:infer` as the value instead.


Example:
```elixir
Telepoison.get!(
  "https://www.example.com/user/list",
  [],
  ot_span_name: "list example users",
  ot_attributes: [{"example.language", "en"}],
  resource_route: "/user/list"
)
```

In the example above, if `:infer` was provided as the value for the `:resource_route` option, it would be inferred as "/user/:subpath".

As is evident, this fallback is rather conservative, so it is highly recommended to supply the `:resource_route` explicitly.

## How it works

Telepoison, when executing an HTTP request to an external service, creates an OpenTelemetry span, injects
the [trace context propagation headers](https://www.w3.org/TR/trace-context/) in the request headers, and
ends the span once the response is received.
It automatically sets some of the [HTTP span attributes](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md) like `http.status`, `http.host` etc,
based on the request and response data.

Telepoison by itself is not particularly useful: it becomes useful when used in conjunction with a "server-side"
opentelemetry-instrumented library, e.g. [opentelemetry_plug](https://github.com/opentelemetry-beam/opentelemetry_plug).
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

* If the request fails due to nxdomain, the `process_response_status_code` hook is not called and therefore
  the span is not ended.

## What's missing

* Set [SpanKind](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/api.md#spankind) to client
* Support for explicit parent span
* Support for fixed span attributes, either in `Teleposion.setup` or in config
* A lot of other stuff..

## Copyright and License

Copyright (c) 2020 Prima.it

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
