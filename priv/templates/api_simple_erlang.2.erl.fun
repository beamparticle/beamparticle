#!erlang
%% @doc Sample Erlang (OTP-20) function to return what was passed in as the first argument.
%% Notice that this template works for the /api/<thisfun> interface, where
%% json input is passed in the first argument postBody, while the response
%% is a binary or a string, which must be json as well.
%%
fun (Body, Context) ->
  DecodedMap = jiffy:decode(Body, [return_maps]),
  %% TODO process decoded_map
  Result = DecodedMap,
  jiffy:encode(Result)
end.
