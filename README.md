# Telepoison

[![Module Version](https://img.shields.io/hexpm/v/telepoison.svg)](https://hex.pm/packages/telepoison)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/telepoison/)
[![Total Download](https://img.shields.io/hexpm/dt/telepoison.svg)](https://hex.pm/packages/telepoison)
[![License](https://img.shields.io/hexpm/l/telepoison.svg)](https://github.com/primait/telepoison/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/primait/telepoison.svg)](https://github.com/primait/telepoison/commits/master)

Telepoison is a [opentelemetry-instrumented](https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/glossary.md#instrumented-library) wrapper around HTTPoison.

## Usage

Call `Telepoison.setup/1` within your application start-up.

Replace usages of the `HTTPoison` module with `Telepoison` when calling one of the *derived* request functions provided by `HTTPoison` (`HTTPoison.get/3`, `HTTPoison.get!/3` etc.)

```elixir
# Before
HTTPoison.get!(url, headers, opts)

# After
Telepoison.get!(url, headers, opts)
```

## Configuration

`Telepoison.setup/1` takes a `Keyword list` that can configure if and how the `http.route` Open Telemetry metadata will be set per request using the `:infer_route` option.

* If no value is provided then the out of the box, conservative inference provided by `Telepoison.URI.infer_route_from_request/1` is used to determine the inference

* If an function with an arity of 1 (the `t:HTTPoison.Request/0` `request`) is provided then that function is used to determine the inference

This can be overridden per each call to `Telepoison.request/1` derived functions (`Telepoison.get/3`, `Telepoison.get!/3` etc.)

## Open Telemetry integration

Additionally, `Telepoison` provides some options that can be added to each derived function via
the `Keyword list` `opts` parameter (or the `HTTPoison.Request` `options` `Keyword list` if calling `Telepoison.Request/1` directly). These are prefixed with `:ot_`.

* `:ot_span_name` - sets the span name.
* `:ot_attributes` - a list of `{name, value}` `tuple` attributes that will be added to the span.
* `:ot_resource_route` - sets the `http.route` attribute, depending on the value provided.

If the value is a string or an function with an arity of 1 (the `t:HTTPoison.Request/0` `request`) that is used to set the attribute

If `:infer` is provided, then the function discussed within the *Configuration* section is used to set the attribute

**It is highly recommended** to supply the `:ot_resource_route` explicitly as either a string or an anonymous function with an arity of 1.

Example:
```elixir
Telepoison.setup(infer_route: :default)

Telepoison.get!(
  "https://www.example.com/user/list",
  [],
  ot_span_name: "list example users",
  ot_attributes: [{"example.language", "en"}],
  ot_resource_route: :infer
)
```

In the example above, as `:infer` was provided as the value for the `:ot_resource_route` option and the out of the box inference configured, the attribute would be inferred as */user/:subpath*.

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
