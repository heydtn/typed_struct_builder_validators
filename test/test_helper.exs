# The dialyzer suite needs a PLT and a few seconds of analysis, so it is opt-in:
# `mix test --only dialyzer`, or `mix test --include dialyzer` alongside the rest.
ExUnit.start(exclude: [:dialyzer])
