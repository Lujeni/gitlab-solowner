FROM elixir:1.15-alpine

RUN apk update && \
  apk add --no-cache git
WORKDIR /app
COPY . .
CMD ["elixir", "inactivity.exs"]
