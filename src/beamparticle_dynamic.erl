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
-export([log_error/2, log_error/1, log_info/2, log_info/1]).
-export([run_concurrent/2,
         async_run_concurrent/2,
         run_concurrent_without_log_and_result/2]).
-export([stage/2, release/1]).

%% @doc Get dynamic function configuration from process dictionary
-spec get_config() -> map().
get_config() ->
    case erlang:get(?CALL_ENV_CONFIG) of
        Config when is_map(Config) -> Config;
        _ -> #{}
    end.

%% @doc Log error for the given dynamic function in current context
-spec log_error(string(), list()) -> ok.
log_error(Format, Args) ->
    EpochNanosec = erlang:system_time(nanosecond),
    B = case erlang:get(?LOG_ENV_KEY) of
            undefined -> {{0, []}, {0, []}};
            A -> A
        end,
    {{OldStdoutLen, OldStdout}, {OldStderrLen, OldStderr}} = B,
    case OldStderrLen of
        _ when OldStderrLen < ?MAX_LOG_EVENTS ->
            Msg = list_to_binary(io_lib:format("~s.~p+00:00 - " ++ Format ++ "~n", [qdate:to_string(<<"Y-m-d H:i:s">>, EpochNanosec div 1000000000), EpochNanosec rem 1000000000 | Args])),
            erlang:put(?LOG_ENV_KEY, {{OldStdoutLen, OldStdout},
                                      {OldStderrLen + 1, [Msg | OldStderr]}});
        _ when OldStderrLen == ?MAX_LOG_EVENTS ->
            erlang:put(?LOG_ENV_KEY, {{OldStdoutLen, OldStdout},
                                      {OldStderrLen + 1, [<<"...">> | OldStderr]}});
        _ ->
            ok
    end.

%% @doc Log error for the given dynamic function in current context
-spec log_error(string()) -> ok.
log_error(Msg) ->
    log_error(Msg, []).

%% @doc Log info for the given dynamic function in current context
-spec log_info(string(), list()) -> ok.
log_info(Format, Args) ->
    EpochNanosec = erlang:system_time(nanosecond),
    B = case erlang:get(?LOG_ENV_KEY) of
            undefined -> {{0, []}, {0, []}};
            A -> A
        end,
    {{OldStdoutLen, OldStdout}, {OldStderrLen, OldStderr}} = B,
    Msg = list_to_binary(io_lib:format("~s.~p+00:00 - " ++ Format ++ "~n", [qdate:to_string(<<"Y-m-d H:i:s">>, EpochNanosec div 1000000000), EpochNanosec rem 1000000000 | Args])),
    case OldStderrLen of
        _ when OldStderrLen < ?MAX_LOG_EVENTS ->
            Msg = list_to_binary(io_lib:format("~s.~p+00:00 - " ++ Format ++ "~n", [qdate:to_string(<<"Y-m-d H:i:s">>, EpochNanosec div 1000000000), EpochNanosec rem 1000000000 | Args])),
            erlang:put(?LOG_ENV_KEY, {{OldStdoutLen + 1, [Msg | OldStdout]},
                                      {OldStderrLen, OldStderr}});
        _ when OldStderrLen == ?MAX_LOG_EVENTS ->
            erlang:put(?LOG_ENV_KEY, {{OldStdoutLen + 1, [<<"...">> | OldStdout]},
                                      {OldStderrLen, OldStderr}});
        _ ->
            ok
    end.

%% @doc Log info for the given dynamic function in current context
-spec log_info(string()) -> ok.
log_info(Msg) ->
    log_info(Msg, []).

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

-spec run_concurrent(Tasks :: [{F :: function(), Args :: list()}],
                     TimeoutMsec :: non_neg_integer()) ->
    list().
run_concurrent(Tasks, TimeoutMsec) when TimeoutMsec >= 0 ->
    ParentPid = self(),
    Ref = erlang:make_ref(),
    EnvKey = erlang:get(?CALL_ENV_KEY), %% stage or production
    UserInfo = erlang:get(?USERINFO_ENV_KEY),
    %% CallTraceEnv = erlang:get(?CALL_TRACE_ENV_KEY),
    %% Dialogue = erlang:get(?DIALOGUE_ENV_KEY),
    %% TODO CALL_ENV_CONFIG must be set for appropriate function (validate)
    %% TODO Pull CALL_TRACE_ENV_KEY if call tracing must be provided for tasks
    %% TODO Pull DIALOGUE_ENV_KEY if tasks supports dialogues
    Pids = lists:foldl(fun(E, AccIn) ->
                               %% Pass some of the environment variables
                               %% like ENV, etc there.
                               %% Additionally, pull logs, etc which are set
                               %% in its process dictionary as well.
                               WPid = erlang:spawn_link(
                                 fun() ->
                                         erlang:put(?CALL_ENV_KEY, EnvKey),
                                         erlang:put(?USERINFO_ENV_KEY, UserInfo),
                                         R = case E of
                                                 {F, A} ->
                                                     %% local functions are always
                                                     %% dynamic call
                                                     FBin = atom_to_binary(F, utf8),
                                                     dynamic_call(FBin, A);
                                                 {M, F, A} ->
                                                     apply(M, F, A)
                                              end,
                                         LogInfo = erlang:get(?LOG_ENV_KEY),
                                         ParentPid ! {Ref, self(), LogInfo, R}
                                 end),
                               [WPid | AccIn]
                       end, [], Tasks),
    OldTrapExitFlag = erlang:process_flag(trap_exit, true),
    Result = receive_concurrent_tasks(Ref, Pids, TimeoutMsec, []),
    erlang:process_flag(trap_exit, OldTrapExitFlag),
    Result.

receive_concurrent_tasks(_Ref, [], _TimeoutMsec, AccIn) ->
    AccIn;
receive_concurrent_tasks(Ref, Pids, TimeoutMsec, AccIn) ->
    T1 = erlang:system_time(millisecond),
    receive
        {Ref, Pid, LogInfo, R} ->
            %% This is time consuming since it is O(N),
            %% but this interface shall not be invoked for very high
            %% concurrency.
            RemainingPids = Pids -- [Pid],
            T2 = erlang:system_time(millisecond),
            merge_function_logs(LogInfo),
            %% Notice that some time has elapsed, so account for that
            receive_concurrent_tasks(Ref, RemainingPids,
                                     TimeoutMsec - (T2 - T1),
                                     [R | AccIn])
    after
        TimeoutMsec ->
            lists:foreach(fun(P) ->
                                  erlang:exit(P, kill)
                          end, Pids),
            {error, {timeout, AccIn}}
    end.

-spec async_run_concurrent(Tasks :: [{F :: function(), Args :: list()}],
                           TimeoutMsec :: non_neg_integer()) ->
    list().
async_run_concurrent(Tasks, TimeoutMsec) ->
    NumSecondsUntilRun = 1,
    JobSpecScheduleOnly = {once, NumSecondsUntilRun},
    JobSpec = {JobSpecScheduleOnly,
               {beamparticle_dynamic,
                run_concurrent_without_log_and_result,
                [Tasks, TimeoutMsec]}},
    lager:debug("async_run_concurrent JobSpec = ~p", [JobSpec]),
    JobRefCreated = erlcron:cron(JobSpec),
    lager:debug("async_run_concurrent JobRefCreated = ~p", [JobRefCreated]),
    JobRefCreated.

-spec run_concurrent_without_log_and_result(
        Tasks :: [{F :: function(), Args :: list()}],
        TimeoutMsec :: non_neg_integer()) ->
    list().
run_concurrent_without_log_and_result(Tasks, TimeoutMsec) when TimeoutMsec >= 0 ->
    ParentPid = self(),
    Ref = erlang:make_ref(),
    EnvKey = erlang:get(?CALL_ENV_KEY), %% stage or production
    UserInfo = erlang:get(?USERINFO_ENV_KEY),
    %% TODO CALL_ENV_CONFIG must be set for appropriate function (validate)
    Pids = lists:foldl(fun(E, AccIn) ->
                               %% Pass some of the environment variables
                               %% like ENV, etc there.
                               WPid = erlang:spawn_link(
                                 fun() ->
                                         erlang:put(?CALL_ENV_KEY, EnvKey),
                                         erlang:put(?USERINFO_ENV_KEY, UserInfo),
                                         case E of
                                             {F, A} ->
                                                 %% local functions are always
                                                 %% dynamic call
                                                 FBin = atom_to_binary(F, utf8),
                                                 dynamic_call(FBin, A);
                                             {M, F, A} ->
                                                 apply(M, F, A)
                                         end,
                                         ParentPid ! {Ref, self()}
                                 end),
                               [WPid | AccIn]
                       end, [], Tasks),
    OldTrapExitFlag = erlang:process_flag(trap_exit, true),
    receive_concurrent_tasks_without_log_and_result(Ref, Pids, TimeoutMsec),
    erlang:process_flag(trap_exit, OldTrapExitFlag),
    ok.

receive_concurrent_tasks_without_log_and_result(_Ref, [], _TimeoutMsec) ->
    ok;
receive_concurrent_tasks_without_log_and_result(Ref, Pids, TimeoutMsec) ->
    T1 = erlang:system_time(millisecond),
    receive
        {Ref, Pid} ->
            %% This is time consuming since it is O(N),
            %% but this interface shall not be invoked for very high
            %% concurrency.
            RemainingPids = Pids -- [Pid],
            T2 = erlang:system_time(millisecond),
            lager:debug("~p - ~p", [T2, {Ref, Pid}]),
            %% Notice that some time has elapsed, so account for that
            receive_concurrent_tasks_without_log_and_result(
              Ref, RemainingPids, TimeoutMsec - (T2 - T1))
    after
        TimeoutMsec ->
            lists:foreach(fun(P) ->
                                  erlang:exit(P, kill)
                          end, Pids),
            lager:error("receive_concurrent_tasks_without_log_and_result {error, timeout}"),
            {error, timeout}
    end.

-spec stage(GitSrcFilename :: string(), State :: term()) -> ok.
stage(GitSrcFilename, State) when is_list(GitSrcFilename) ->
    erlang:put(?CALL_ENV_KEY, stage), %% TODO read the config for prod in sys.config and act accordingly
    GitBackendConfig = application:get_env(?APPLICATION_NAME, gitbackend, []),
    GitRootPath = proplists:get_value(rootpath, GitBackendConfig, "./"),
    GitSrcPath = GitRootPath ++ "/git-src/" ++ GitSrcFilename,
    case file:read_file(GitSrcPath) of
        {ok, FunctionBody} ->
            [FunctionNameStr | _] = string:split(GitSrcFilename, "."),
            FunctionName = list_to_binary(FunctionNameStr),
            R1 = beamparticle_ws_handler:handle_save_command(FunctionName, FunctionBody, State),
            {reply, {text, JsonResp1}, _, _} = R1,
            RespMap = jiffy:decode(JsonResp1, [return_maps]),
            {proplists, [{<<"html">>, maps:get(<<"html">>, RespMap, <<>>)},
                         {<<"text">>, maps:get(<<"text">>, RespMap, <<>>)}]};
            %% lager:info("beamparticle_ws_handler:handle_save_command(~p, ~p, ~p)", [FunctionName, FunctionBody, State]),
            %% Msg = <<"NOT implemented">>,
            %% {reply, {text, jiffy:encode(#{<<"speak">> => Msg, <<"text">> => Msg})}, State, hibernate};
        _ ->
            Msg = iolist_to_binary([<<"Error: Cannot find file ">>, list_to_binary(GitSrcPath)]),
            {proplists, [{<<"speak">>, Msg}, {<<"text">>, Msg}]}
            %% {reply, {text, jiffy:encode(#{<<"speak">> => Msg, <<"text">> => Msg})}, State, hibernate}
    end.

-spec release(State :: term()) -> ok.
release(State) ->
    R = beamparticle_ws_handler:handle_release_command(State),
    {reply, {text, JsonResp}, _, _} = R,
    RespMap = jiffy:decode(JsonResp, [return_maps]),
    {proplists, [{<<"html">>, maps:get(<<"html">>, RespMap, <<>>)},
                 {<<"text">>, maps:get(<<"text">>, RespMap, <<>>)}]}.


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
                lager:error("~p(~p) ~p:~p", [DynamicFunctionName, Arguments, Class, Error]),
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
    DynamicFunctionLogs = case erlang:get(?LOG_ENV_KEY) of
                             {{_, Stdout}, {_, Stderr}} ->
                                  %% The logs are stored in reverse, so
                                  %% reverse again before sending it out.
                                  [{<<"log_stdout">>,
                                    iolist_to_binary(lists:reverse(Stdout))},
                                   {<<"log_stderr">>,
                                    iolist_to_binary(lists:reverse(Stderr))}];
                             _ ->
                                 []
                          end,
    case Result of
        {error, invalid_function} ->
            Msg = <<"It is not a valid Erlang expression!">>,
            HtmlResponse = <<"">>,
            Json = #{},
            [{<<"speak">>, Msg},
             {<<"text">>, Msg},
             {<<"html">>, HtmlResponse},
             {<<"json">>, Json} | DynamicFunctionLogs];
        _ ->
            lager:debug("Result2 = ~p", [Result]),
            case Result of
                {proplists, PropLists} ->
                    lists:flatten([PropLists | DynamicFunctionLogs]);
                _ ->
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
                     {<<"json">>, Json} | DynamicFunctionLogs]
            end
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

merge_function_logs(undefined) ->
    ok;
merge_function_logs({{StdoutLen, Stdout}, {StderrLen, Stderr}}) ->
    case erlang:get(?LOG_ENV_KEY) of
        {{OldStdoutLen, OldStdout}, {OldStderrLen, OldStderr}} ->
            {UpdatedStdoutLen, UpdatedStdout} =
            case StdoutLen + OldStdoutLen of
                A when A < ?MAX_LOG_EVENTS ->
                    {A, Stdout ++ OldStdout};
                _ ->
                    {OldStdoutLen, OldStdout}
            end,
            {UpdatedStderrLen, UpdatedStderr} =
            case StderrLen + OldStderrLen of
                B when B < ?MAX_LOG_EVENTS ->
                    {B, Stderr ++ OldStderr};
                _ ->
                    {OldStderrLen, OldStderr}
            end,
            erlang:put(?LOG_ENV_KEY,
                       {{UpdatedStdoutLen, UpdatedStdout},
                        {UpdatedStderrLen, UpdatedStderr}});
        _ ->
            erlang:put(?LOG_ENV_KEY,
                       {{StdoutLen, Stdout}, {StderrLen, Stderr}})
    end.
