#!elixir
#
# api_simple_elixir
#
# Sample Elixir function to return what was passed in as the first argument.
# Notice that this template works for the /api/<thisfun> interface, where
# json input is passed in the first argument postBody, while the response
# is a binary or a string, which must be json as well.

fn (body, context) ->
  decoded_map = :jiffy.decode(body, [:return_maps])
  # TODO process decoded_map
  result = decoded_map
  :jiffy.encode(result)
end
