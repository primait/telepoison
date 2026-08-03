FROM 279066465364.dkr.ecr.eu-west-1.amazonaws.com/prima-elixir:1.17.3

WORKDIR /code

USER app

COPY ["entrypoint", "/entrypoint"]

ENTRYPOINT ["/entrypoint"]
