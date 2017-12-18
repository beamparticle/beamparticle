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
-module(beamparticle_efeneparser).

-include("beamparticle_constants.hrl").

-export([
    evaluate_efene_expression/1,
    get_erlang_parsed_expressions/1
]).

%% @doc Evaluate a given Efene expression and give back result.
%%
%% Hint: https://github.com/efene/efene/blob/master/src/fn_repl.erl
%%
%% IMPORTANT: Start comment with #_ and then enclosed text in double quotes.
%% IMPORTANT: Enclose comments in double quotes is important
%%            else efene compiler tries to evaluate the expression.
%%
%% Sample EfeneExpression
%% ```
%% #!efene
%% #_ "first comment line shown in help"
%% #_ "Another comment which must be in double quotes as well"
%% #_ "Notice that the terminating dot is not required here unlike in Erlang"
%% fn
%%     case A, A: false
%%     case _, _: true
%% end
%% '''
-spec evaluate_efene_expression(string() | binary()) -> any().
evaluate_efene_expression(EfeneExpression) ->
    EfeneExpressionStr = case is_binary(EfeneExpression) of
                             true ->
                                 binary_to_list(EfeneExpression);
                             false ->
                                 EfeneExpression
                         end,
    {ok, Ast} = efene:str_to_ast(EfeneExpressionStr),
    State0 = fn_to_erl:new_state("beamparticle", "beamparticle"),
    State = State0#{level => 1},
    {ErlangParsedExpressions, _State2} = fn_to_erl:ast_to_ast(Ast, State),
    beamparticle_erlparser:evaluate_erlang_parsed_expressions(ErlangParsedExpressions).

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(EfeneExpression) when is_binary(EfeneExpression) ->
    get_erlang_parsed_expressions(binary_to_list(EfeneExpression));
get_erlang_parsed_expressions(EfeneExpression) when is_list(EfeneExpression) ->
    {ok, Ast} = efene:str_to_ast(EfeneExpression),
    State0 = fn_to_erl:new_state("beamparticle", "beamparticle"),
    State = State0#{level => 1},
    {ErlangParsedExpressions, _State2} = fn_to_erl:ast_to_ast(Ast, State),
    ErlangParsedExpressions.

