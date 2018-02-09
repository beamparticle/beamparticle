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
-export([dynamic_call/2, get_result/1, get_result/2, get_raw_result/2]).
-export([transform_result/1]).
-export([execute/1]).
-export([get_config/0, put_config/1, erase_config/0, parse_config/1]).

%% @doc Get dynamic function configuration from process dictionary
-spec get_config() -> map().
get_config() ->
    case erlang:get(?CALL_ENV_CONFIG) of
        Config when is_map(Config) -> Config;
        _ -> #{}
    end.

%% @doc Save dynamic function configuration to process dictionary
-spec put_config(map() | undefined) -> ok.
put_config(undefined) ->
    erase_config();
put_config(ConfigMap) ->
    erlang:put(?CALL_ENV_CONFIG, ConfigMap).

%% @doc Erase dynamic function configuration from process dictionary
-spec erase_config() -> ok.
erase_config() ->
    erlang:erase(?CALL_ENV_CONFIG).

%% @doc Parse json configuration
-spec parse_config(binary()) -> {ok, map()} | {error, invalid}.
parse_config(<<>>) ->
    {ok, #{}};
parse_config(Config) when is_binary(Config) ->
    try
        {ok, jiffy:decode(Config, [return_maps])}
    catch
        _:_ ->
            {error, invalid}
    end.

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

execute(Expression) when is_binary(Expression) ->
    EnableTrace = try_enable_opentracing(),
    Result =
        try
            EvaluateResp = beamparticle_erlparser:evaluate_expression(Expression),
            case EvaluateResp of
                {F, Config} when is_function(F, 0) ->
                    try
                        case parse_config(Config) of
                            {ok, ConfigMap} ->
                                put_config(ConfigMap);
                            _ ->
                                ok
                        end,
                        R2 = apply(F, []),
                        erase_config(),
                        R2
                    catch
                        throw:{error, R} ->
                            {text, R}
                    end;
                _ ->
                    case EvaluateResp of
                        {php, PhpCode, Config, _CompileType} ->
                            beamparticle_phpparser:evaluate_php_expression(
                                            PhpCode, Config, []);
                        {python, PythonCode, Config, _CompileType} ->
                            %% We can handle undefined function name
                            %% use {eval, Code} in
                            %% beamparticle_python_server:call/2
                            beamparticle_pythonparser:evaluate_python_expression(
                                            undefined, PythonCode, Config, []);
                        {java, JavaCode, Config, _CompileType} ->
                            %% We can handle undefined function name
                            %% use {eval, Code} in
                            %% beamparticle_java_server:call/2
                            beamparticle_javaparser:evaluate_java_expression(
                                            undefined, JavaCode, Config, []);
                        _ ->
                            lager:error("EvaluateResp = ~p is invalid", [EvaluateResp]),
                            {error, invalid_function}
                    end
            end
        catch
            Class:Error ->
                lager:error("~p:~p, stacktrace = ~p", [Class, Error, erlang:get_stacktrace()]),
                {error, {Class, Error}}
        end,
    close_opentracing(EnableTrace),
    Result;
execute({DynamicFunctionName, Arguments}) ->
    FunctionNameBin = DynamicFunctionName,
    EnableTrace = try_enable_opentracing(),
    Result =
        try
            beamparticle_erlparser:execute_dynamic_function(FunctionNameBin, Arguments)
        catch
            Class:Error ->
                lager:error("~p:~p", [Class, Error]),
                {error, {Class, Error}}
        end,
    close_opentracing(EnableTrace),
    Result.

get_result(FunctionName, Arguments) when is_binary(FunctionName) andalso is_list(Arguments) ->
    lager:debug("get_response(~p, ~p)", [FunctionName, Arguments]),
    Result = execute({FunctionName, Arguments}),
    transform_result(Result).

get_result(Expression) when is_binary(Expression) ->
    lager:debug("get_response(~p)", [Expression]),
    Result = execute(Expression),
    transform_result(Result).

get_raw_result(FunctionName, Arguments) when is_binary(FunctionName) andalso is_list(Arguments) ->
    lager:debug("get_raw_result(~p, ~p)", [FunctionName, Arguments]),
    %% apply prefix so that downstream functions can
    %% appropriate pass that information, which is at present used by
    %% java and python functions
    Result = execute({<<"__simple_http_", FunctionName/binary>>, Arguments}),
    case is_binary(Result) of
        true ->
            Result;
        false ->
            list_to_binary(io_lib:format("~p", [Result]))
    end.

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
