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
-module(beamparticle_phpparser).

-include("beamparticle_constants.hrl").

-include_lib("ephp/include/ephp.hrl").

-export([
    evaluate_php_expression/2,
    get_erlang_parsed_expressions/1,
    validate_php_function/1,
    convert_erlang_to_php_value/1,
    convert_php_to_erlang_value/1
]).

%% @doc Evaluate a given Php expression and give back result.
%%
%% Hint: https://github.com/bragful/ephp/tree/test/ephp_request_test.erl
%%
%% IMPORTANT: "#!php" is header marker
%% IMPORTANT: <?php ... ?> is used as in PHP, but you can use
%%            them as you like in regular PHP program.
%%            If the output of the Php expression do not
%%            start with "erlang_term:" then it is treated
%%            as a binary() output.
%%
%% Sample PhpExpression
%% ```
%% #!php
%% <?php
%% // first comment line shown in help
%% // Another comment which must be in double quotes as well
%% // Need main function, which will be invoked as the first function call.
%% function main($num)
%% {
%%     return $num * $num;
%% }
%% ?>
%% '''
-spec evaluate_php_expression(string() | binary(), [term()]) -> any().
evaluate_php_expression(PhpExpression, Arguments) when is_list(Arguments) ->
    PhpExpressionStr = case is_binary(PhpExpression) of
                             true ->
                                 binary_to_list(PhpExpression);
                             false ->
                                 PhpExpression
                         end,
    lager:debug("PhpExpression = ~p, Arguments = ~p", [PhpExpression, Arguments]),
    {ok, Ctx} = ephp:context_new(),

    %% apply crossover module so that PHP can call dynamic functions
    ephp:register_module(Ctx, beamparticle_php_lib_crossover),

    %% Extract Php Arguments
    %% convert Aguments to Php variables and
    %% use ephp_context:set(Ctx, #variable{name = <<"_REQUEST">>}, ReqArray)
    %% see https://github.com/bragful/ephp/tree/test/ephp_request_test.erl
    PhpArguments = lists:reverse(lists:foldl(fun(E, AccIn) ->
                        lager:debug("convert_erlang_to_php_value(~p)", [E]),
                        [convert_erlang_to_php_value(E) | AccIn]
                                             end, [], Arguments)),
    %% try to capture the output
    {ok, Output} = ephp_output:start_link(Ctx, false),
    ephp_context:set_output_handler(Ctx, Output),
    Compiled = ephp_parser:parse(PhpExpressionStr),
    {ok, _Text} = ephp_interpr:process(Ctx, Compiled, false),
    %% extract global variable from context, which would be set
    %% ModReqArray = ephp_context:get(Ctx, #variable{name = <<"_REQUEST">>})
    Call = #call{name = <<"main">>, args = PhpArguments},
    Result = ephp_context:call_function(Ctx, Call),
    lager:debug("Result = ~p", [Result]),
    convert_php_to_erlang_value(Result).

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(PhpExpression) when is_binary(PhpExpression)
    orelse is_list(PhpExpression) ->
    undefined.

-spec validate_php_function(string() | binary())
        -> {ok, Arity :: integer()} | {error, term()}.
validate_php_function(PhpExpression) ->
    PhpExpressionStr = case is_binary(PhpExpression) of
                             true ->
                                 binary_to_list(PhpExpression);
                             false ->
                                 PhpExpression
                         end,
    lager:debug("PhpExpression = ~p", [PhpExpression]),
    {ok, Ctx} = ephp:context_new(),
    try
        %% try to capture the output
        {ok, Output} = ephp_output:start_link(Ctx, false),
        ephp_context:set_output_handler(Ctx, Output),
        Compiled = ephp_parser:parse(PhpExpressionStr),
        {ok, _Text} = ephp_interpr:process(Ctx, Compiled, false),
        MainFunResp = ephp_func:get(ephp_context:get_funcs(Ctx), <<"main">>),
        ephp_context:destroy_all(Ctx),
        case MainFunResp of
            error ->
                {error, <<"main() function is missing">>};
            {ok, MainFunRec} ->
                {ok, length(MainFunRec#reg_func.args)}
        end
    catch
        C:E ->
            lager:error("error compiling PHP ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            ephp_context:destroy_all(Ctx),
            {error, {exception, {C, E}}}
    end.

convert_erlang_to_php_value(Val) when is_boolean(Val) orelse is_integer(Val)
                                    orelse is_float(Val)
                                    orelse is_binary(Val) ->
    Val;
convert_erlang_to_php_value(Val) when is_atom(Val) ->
    atom_to_binary(Val, utf8);
convert_erlang_to_php_value(Val) when is_list(Val) ->
    PhpArray = ephp_array:new(),
    lists:foldl(fun(E, AccIn) ->
                        PhpValue = convert_erlang_to_php_value(E),
                        ephp_array:store(auto, PhpValue, AccIn)
                end, PhpArray, Val);
    %%ephp_array:from_list(Val);
convert_erlang_to_php_value(Val) when is_tuple(Val) ->
    convert_erlang_to_php_value(erlang:tuple_to_list(Val));
convert_erlang_to_php_value(Val) when is_map(Val) ->
    PhpArray = ephp_array:new(),
    maps:fold(fun(K, V, AccIn) ->
                      PhpKey = convert_erlang_to_php_value(K),
                      PhpValue = convert_erlang_to_php_value(V),
                      ephp_array:store(PhpKey, PhpValue, AccIn)
            end, PhpArray, Val).

convert_php_to_erlang_value(Val) when ?IS_ARRAY(Val) ->
    PropList = ephp_array:to_list(Val),
    {Keys, Values} = lists:unzip(PropList),
    SeqNumbers = lists:seq(0, length(Keys) - 1),
    case Keys of
        SeqNumbers ->
            %% return list if the Keys are 0..N
            lists:foldr(fun(E, AccIn) ->
                                [convert_php_to_erlang_value(E) | AccIn]
                        end, [], Values);
        _ ->
            %% else it is a map
            lists:foldl(fun({K, V}, AccIn) ->
                                ErlK = convert_php_to_erlang_value(K),
                                ErlV = convert_php_to_erlang_value(V),
                                AccIn#{ErlK => ErlV}
                        end, #{}, PropList)
            %%maps:from_list(PropList)
    end;
convert_php_to_erlang_value(Val) ->
    Val.
