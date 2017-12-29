%%% %CopyrightBegin%
%%%
%%% Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
%%% All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% %CopyrightEnd%
-module(beamparticle_elixirparser).

-include("beamparticle_constants.hrl").

-export([
    evaluate_elixir_expression/2,
    get_erlang_parsed_expressions/1
]).

%% @doc Evaluate a given Elixir expression and give back result.
%%
%% Hint: https://github.com/elixir-lang/elixir/blob/master/lib/elixir/test/erlang/test_helper.erl
%%
%% Sample ElixirExpression
%% ```
%% #!elixir
%% # first comment line shown in help
%% # Another comment
%% fn (a, b) ->
%%     a + b
%% end
%% '''
-spec evaluate_elixir_expression(string() | binary(), normal | optimize)
        -> any().
evaluate_elixir_expression(ElixirExpression, CompileType) ->
    ElixirExpressionStr = case is_binary(ElixirExpression) of
                             true ->
                                 binary_to_list(ElixirExpression);
                             false ->
                                 ElixirExpression
                         end,
    Forms = elixir:'string_to_quoted!'(ElixirExpressionStr, 1, <<"nofile">>, []),
    {ErlangParsedExpression, _NewEnv, _NewScope} = elixir:quoted_to_erl(Forms, elixir:env_for_eval([])),
    beamparticle_erlparser:evaluate_erlang_parsed_expressions(
      [ErlangParsedExpression], CompileType).

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(ElixirExpression) when is_binary(ElixirExpression) ->
    get_erlang_parsed_expressions(binary_to_list(ElixirExpression));
get_erlang_parsed_expressions(ElixirExpression) when is_list(ElixirExpression) ->
    StartLine = 1,
    File = <<"nofile">>,
    Forms = elixir:'string_to_quoted!'(ElixirExpression, StartLine, File, []),
    {ErlangParsedExpression, _NewEnv, _NewScope} = elixir:quoted_to_erl(Forms, elixir:env_for_eval([])),
    [ErlangParsedExpression].

