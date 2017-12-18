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
-module(beamparticle_dynamic).

-include("beamparticle_constants.hrl").

-export([create_pool/7]).
-export([dynamic_call/2, execute/2, execute/1, get_result/1, get_result/2]).
-export([transform_result/1]).


%% @doc Create a pool of dynamic function with given configuration
-spec create_pool(PoolName :: atom(),
                  PoolSize :: pos_integer(),
                  PoolWorkerId :: atom(),
                  ShutdownDelayMsec :: pos_integer(),
                  MinAliveRatio :: float(),
                  ReconnectDelayMsec :: pos_integer(),
                  DynamicFunctionName :: binary())
        -> {ok, pid()} | {error, term()}.
create_pool(PoolName, PoolSize, PoolWorkerId, ShutdownDelayMsec,
            MinAliveRatio, ReconnectDelayMsec,
            DynamicFunctionName) ->
    beamparticle_generic_pool_worker:create_pool(
      PoolName, PoolSize, PoolWorkerId, ShutdownDelayMsec,
      MinAliveRatio, ReconnectDelayMsec,
      {fun ?MODULE:dynamic_call/2, DynamicFunctionName}).

dynamic_call(FunctionNameBin, Arguments)
    when is_binary(FunctionNameBin) andalso is_list(Arguments) ->
    execute({FunctionNameBin, Arguments});
dynamic_call(FunctionNameBin, Argument)
    when is_binary(FunctionNameBin) ->
    execute({FunctionNameBin, [Argument]}).

execute(Fun, Arguments) when is_function(Fun)
                             andalso is_list(Arguments) ->
    EnableTrace = try_enable_opentracing(),
    Result =
        try
            apply(Fun, Arguments)
        catch
            throw:{error, R} ->
                {text, R};
            Class:Error ->
                lager:error("~p:~p", [Class, Error]),
                {error, {Class, Error}}
        end,
    close_opentracing(EnableTrace),
    Result.

execute(Expression) when is_binary(Expression) ->
    EnableTrace = try_enable_opentracing(),
    Result =
        try
            F = beamparticle_erlparser:evaluate_expression(binary_to_list(Expression)),
            case is_function(F, 0) of
                true ->
                    try
                        apply(F, [])
                    catch
                        throw:{error, R} ->
                            {text, R}
                    end;
                false ->
                    lager:error("Function F = ~p is invalid", [F]),
                    {error, invalid_function}
            end
        catch
            Class:Error ->
                lager:error("~p:~p", [Class, Error]),
                {error, {Class, Error}}
        end,
    close_opentracing(EnableTrace),
    Result;
execute({DynamicFunctionName, Arguments}) ->
    %% Lookup function cache and use that instead of
    %% compiling the function at this time.
    %% This is a major time saver, so use it whenever possible.
    FunctionNameBin = DynamicFunctionName,
    Arity = length(Arguments),
    ArityBin = integer_to_binary(Arity, 10),
    FullFunctionName = <<FunctionNameBin/binary, $/, ArityBin/binary>>,
    case beamparticle_cache_util:get(FullFunctionName) of
        {ok, Fun} ->
            erlang:put(?OPENTRACE_PDICT_NAME, DynamicFunctionName),
            execute(Fun, Arguments);
        _ ->
            ArgBin = list_to_binary(lists:join(",", [io_lib:format("~p", [Y]) || Y <- Arguments])),
            FunctionBody = <<"fun() -> ", DynamicFunctionName/binary, "(", ArgBin/binary, ")\nend.">>,
            lager:debug("Running function = ~p", [FunctionBody]),
            erlang:put(?OPENTRACE_PDICT_NAME, DynamicFunctionName),
            execute(FunctionBody)
    end.

get_result(FunctionName, Arguments) when is_binary(FunctionName) andalso is_list(Arguments) ->
    lager:debug("get_response(~p, ~p)", [FunctionName, Arguments]),
    Result = execute({FunctionName, Arguments}),
    transform_result(Result).

get_result(Expression) when is_binary(Expression) ->
    lager:debug("get_response(~p)", [Expression]),
    Result = execute(Expression),
    transform_result(Result).

transform_result(Result) ->
    case Result of
        {error, invalid_function} ->
            Msg = <<"It is not a valid Erlang expression!">>,
            HtmlResponse = <<"">>,
            Json = #{},
            [{<<"speak">>, Msg},
             {<<"text">>, Msg},
             {<<"html">>, HtmlResponse},
             {<<"json">>, Json}];
        _ ->
            lager:debug("Result2 = ~p", [Result]),
            {Msg, HtmlResponse, Json} = case Result of
                                      {direct, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {speak, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {text, M} when is_binary(M) ->
                                          {M, <<"">>, #{}};
                                      {html, M} when is_binary(M) ->
                                          {<<"">>, M, #{}};
                                      {json, M} when is_map(M) ->
                                          {<<"">>, <<"">>, M};
                                      _ ->
                                          {<<"">>, list_to_binary(
                                            io_lib:format("~p", [Result])), #{}}
                                  end,
            [{<<"speak">>, Msg},
             {<<"text">>, Msg},
             {<<"html">>, HtmlResponse},
             {<<"json">>, Json}]
    end.

try_enable_opentracing() ->
    OpenTracingConfig = application:get_env(
                          ?APPLICATION_NAME, opentracing, []),
    EnableTrace =
        case OpenTracingConfig of
            [] ->
                true;
            _ ->
                proplists:get_value(enable, OpenTracingConfig, true)
        end,
    case EnableTrace of
        true ->
            OpenTraceNameBin = case erlang:get(?OPENTRACE_PDICT_NAME) of
                                   undefined ->
                                       atom_to_binary(?APPLICATION_NAME, utf8);
                                   NameBin ->
                                       NameBin
                               end,
            %% save to process dictionary for fast access
            erlang:put(?OPENTRACE_PDICT_CONFIG, OpenTracingConfig),
            otter_span_pdict_api:start(OpenTraceNameBin);
        false ->
            ok
    end,
    EnableTrace.

close_opentracing(EnableTrace) ->
    case EnableTrace of
        true ->
            otter_span_pdict_api:finish();
        false ->
            ok
    end.
