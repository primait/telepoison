FROM public.ecr.aws/prima/elixir:1.17.3

WORKDIR /code

USER app

COPY ["entrypoint", "/entrypoint"]

ENTRYPOINT ["/entrypoint"]
