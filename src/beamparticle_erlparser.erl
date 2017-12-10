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
-module(beamparticle_erlparser).
 
-include("beamparticle_constants.hrl").

-export([
    evaluate_erlang_expression/1,
    calltrace_to_json_map/1,
    discover_function_calls/1
]).
 
%% @doc Evaluate a given Erlang expression and give back result.
%%
%% Only local functions are intercepted, while the external
%% functions are pass through. This is dangerous, but necessary
%% for maximum flexibity to call any function.
%% If required this can be modified to intercept external
%% module functions as well to jail them within a limited set.
-spec evaluate_erlang_expression(string() | binary()) -> any().
evaluate_erlang_expression(ErlangExpression) ->
    {ok, ErlangTokens, _} = erl_scan:string(ErlangExpression),
    {ok, ErlangParsedExpressions} = erl_parse:parse_exprs(ErlangTokens),
    {value, Result, _} = erl_eval:exprs(ErlangParsedExpressions, [],
                                        {value, fun intercept_local_function/2}),
    Result.

calltrace_to_json_map(CallTrace) when is_list(CallTrace) ->
    lists:foldl(fun({FunctionName, Arguments, DeltaUsec}, AccIn) ->
                        [#{<<"function">> => FunctionName,
                           <<"arguments">> => list_to_binary(io_lib:format("~p", [Arguments])),
                           <<"delta_usec">> => DeltaUsec} | AccIn]
                end, [], CallTrace).
 
%% @private
%% @doc Intercept calls to local function and patch them in.
-spec intercept_local_function(FunctionName :: atom(),
                               Arguments :: list()) -> any().
intercept_local_function(FunctionName, Arguments) ->
    lager:debug("Local call to ~p with ~p~n", [FunctionName, Arguments]),
    case FunctionName of
        _ ->
            FunctionNameBin = atom_to_binary(FunctionName, utf8),
            Arity = length(Arguments),
            ArityBin = integer_to_binary(Arity, 10),
            FullFunctionName = <<FunctionNameBin/binary, $/, ArityBin/binary>>,
            case erlang:get(?CALL_TRACE_KEY) of
                undefined ->
                    ok;
                OldCallTrace ->
                    T1 = erlang:monotonic_time(micro_seconds),
                    T = erlang:get(?CALL_TRACE_BASE_TIME),
                    erlang:put(?CALL_TRACE_KEY, [{FunctionNameBin, Arguments, T1 - T} | OldCallTrace])
            end,
            FResp = case timer:tc(beamparticle_cache_util, get, [FullFunctionName]) of
                        {CacheLookupTimeUsec, {ok, Func}} ->
                            lager:debug("Took ~p usec for cache hit of ~s", [CacheLookupTimeUsec, FullFunctionName]),
                            {ok, Func};
                        {CacheLookupTimeUsec, _} ->
                            lager:debug("Took ~p usec for cache miss of ~s", [CacheLookupTimeUsec, FullFunctionName]),
                            T2 = erlang:monotonic_time(micro_seconds),
                            KvResp = beamparticle_storage_util:read(
                                     FullFunctionName, function),
                            case KvResp of
                                {ok, FunctionBody} ->
                                    Func2 = beamparticle_erlparser:evaluate_erlang_expression(
                                              binary_to_list(FunctionBody)),
                                    T3 = erlang:monotonic_time(micro_seconds),
                                    lager:debug("Took ~p micro seconds to read and compile ~s function",[T3 - T2, FullFunctionName]),
                                    beamparticle_cache_util:async_put(FullFunctionName, Func2),
                                    {ok, Func2};
                                _ ->
                                    {error, not_found}
                            end
                    end,
            case FResp of
                {ok, F} ->
                    apply(F, Arguments);
                _ ->
                    lager:debug("FunctionNameBin=~p, Arguments=~p", [FunctionNameBin, Arguments]),
                    R = list_to_binary(io_lib:format("Please teach me what must I do with ~s(~s)", [FunctionNameBin, lists:join(",", [io_lib:format("~p", [X]) || X <- Arguments])])),
                    lager:info("R=~p", [R]),
                    erlang:throw({error, R})
            end
    end.
 
%% @doc Discover function calls from the given anonymous function.
%%
%% This function recurisively digs into the function body and finds
%% any further function calls (local or remote) and returns back
%% unique list of function calls made by the provided anonymous
%% function. You could either give the function definition or
%% compiled function.
%%
%% IMPORTANT: There is an order of 10 difference between the
%% runtime when invoked with function body instead of the
%% compiled function. Use the
%% discover_function_calls(fun()) whenever possible to get
%% 10x speed.
%%
%% ```
%%   {ok, Content} = file:read_file("sample-2.erl.fun"),
%%   beamparticle_erlparser:discover_function_calls(Content).
%% '''
-spec discover_function_calls(fun() | string() | binary()) -> any().
discover_function_calls(ErlangExpression) when is_binary(ErlangExpression) ->
    discover_function_calls(binary_to_list(ErlangExpression));
discover_function_calls(ErlangExpression) when is_list(ErlangExpression) ->
    {ok, ErlangTokens, _} = erl_scan:string(ErlangExpression),
    {ok, ErlangParsedExpressions} = erl_parse:parse_exprs(ErlangTokens),
    Functions = recursive_dig_function_calls(ErlangParsedExpressions, []),
    lists:usort(Functions);
discover_function_calls(F) when is_function(F) ->
    {env, FunCodeAsEnv} = erlang:fun_info(F, env),
    Functions = recursive_dig_function_calls(FunCodeAsEnv, []),
    lists:usort(Functions).

%% @private
%% @doc Recursively dig and extract function calls (if any)
%%
%% The function returns a list of {Module, Fun, Arity} or
%% {Fun, Arity} (for local functions).
-spec recursive_dig_function_calls(term(), list())
    -> [{atom(), atom(), integer()} | {atom(), integer()}].
recursive_dig_function_calls([], AccIn) ->
    AccIn;
recursive_dig_function_calls([H | Rest], AccIn) ->
    AccIn2 = recursive_dig_function_calls(H, AccIn),
    recursive_dig_function_calls(Rest, AccIn2);
recursive_dig_function_calls({[], _, _, Clauses}, AccIn) ->
    %% This matches the case when erlang:fun_info/1 is used
    recursive_dig_function_calls(Clauses, AccIn);
recursive_dig_function_calls({'fun', _LineNum, ClausesRec}, AccIn) ->
    recursive_dig_function_calls(ClausesRec, AccIn);
recursive_dig_function_calls({clauses, [H | RestClauses]}, AccIn) ->
    AccIn2 = recursive_dig_function_calls(H, AccIn),
    recursive_dig_function_calls(RestClauses, AccIn2);
recursive_dig_function_calls({clause, _LineNum, _, _, Expressions}, AccIn) ->
    recursive_dig_function_calls(Expressions, AccIn);
recursive_dig_function_calls({match, _LineNum, Lhs, Rhs}, AccIn) ->
    AccIn2 = recursive_dig_function_calls(Lhs, AccIn),
    recursive_dig_function_calls(Rhs, AccIn2);
recursive_dig_function_calls({var, _LineNum, _VarName}, AccIn) ->
    AccIn;
recursive_dig_function_calls({op, _LineNum, _Op, Lhs, Rhs}, AccIn) ->
    %% binary operator
    AccIn2 = recursive_dig_function_calls(Lhs, AccIn),
    recursive_dig_function_calls(Rhs, AccIn2);
recursive_dig_function_calls({op, _LineNum, _Op, Rhs}, AccIn) ->
    %% unary operator
    recursive_dig_function_calls(Rhs, AccIn);
recursive_dig_function_calls({'case', _LineNum, Condition, Branches}, AccIn) ->
    AccIn2 = recursive_dig_function_calls(Condition, AccIn),
    recursive_dig_function_calls(Branches, AccIn2);
recursive_dig_function_calls({call, _LineNum, {atom, _LineNum2, FunNameAtom}, Args}, AccIn) ->
    Arity = length(Args),
    recursive_dig_function_calls(Args, [{FunNameAtom, Arity} | AccIn]);
recursive_dig_function_calls({call, _LineNum, {remote, _LineNum2, {atom, _LineNum3, ModuleNameAtom}, {atom, _LineNum4, FunNameAtom}}, Args}, AccIn) ->
    Arity = length(Args),
    recursive_dig_function_calls(Args, [{ModuleNameAtom, FunNameAtom, Arity} | AccIn]);
recursive_dig_function_calls({map, _LineNum, _Var, Fields}, AccIn) ->
    recursive_dig_function_calls(Fields, AccIn);
recursive_dig_function_calls({map_field_assoc, _LineNum, Key, Value}, AccIn) ->
    AccIn2 = recursive_dig_function_calls(Key, AccIn),
    recursive_dig_function_calls(Value, AccIn2);
recursive_dig_function_calls({tuple, _LineNum, Fields}, AccIn) ->
    recursive_dig_function_calls(Fields, AccIn);
recursive_dig_function_calls({cons, _LineNum, Arg1, Arg2}, AccIn) ->
    AccIn2 = recursive_dig_function_calls(Arg1, AccIn),
    recursive_dig_function_calls(Arg2, AccIn2);
recursive_dig_function_calls(_, AccIn) ->
    AccIn.

