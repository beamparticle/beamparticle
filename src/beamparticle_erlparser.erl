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
    calltrace_to_json_map/1
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
 
