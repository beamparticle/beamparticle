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
-module(beamparticle_pythonparser).

-include("beamparticle_constants.hrl").

-export([
    evaluate_python_expression/4,
    get_erlang_parsed_expressions/1,
    validate_python_function/2
]).

%% @doc Evaluate a given Python expression and give back result.
%%
%% IMPORTANT: "#!python" is header marker
%%
%% Sample PythonExpression
%% ```
%% #!python
%% 1 + 1
%% '''
%%
%% Another PythonExpression
%% ```
%% #!python
%%
%% def add(a, b):
%%   return a + b
%% '''
-spec evaluate_python_expression(binary() | undefined, string() | binary(),
                                string() | binary(), [term()]) -> any().
evaluate_python_expression(FunctionNameBin, PythonExpression, Config, Arguments) when is_list(PythonExpression) ->
    PythonExpressionBin = list_to_binary(PythonExpression),
    evaluate_python_expression(FunctionNameBin, PythonExpressionBin, Config, Arguments);
evaluate_python_expression(undefined, PythonExpressionBin, _Config, []) ->
    %% TODO use Config
    lager:debug("FunctionNameBin = ~p, PythonExpressionBin = ~p, Arguments = ~p",
                [undefined, PythonExpressionBin, []]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME
        Result = beamparticle_python_server:call({eval, PythonExpressionBin},
                                                 TimeoutMsec),
        lager:debug("Result = ~p", [Result]),
        extract_logs(Result)
    catch
        C:E ->
            lager:error("error compiling Python ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end;
evaluate_python_expression(FunctionNameBin, PythonExpressionBin, ConfigBin, Arguments) when is_list(Arguments) ->
    lager:debug("FunctionNameBin = ~p, PythonExpressionBin = ~p, Arguments = ~p",
                [FunctionNameBin, PythonExpressionBin, Arguments]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME
        Command = case FunctionNameBin of
                      <<"__simple_http_", RealFunctionNameBin/binary>> ->
                          [DataBin, ContextBin] = Arguments,
                          {invoke_simple_http, RealFunctionNameBin, PythonExpressionBin, ConfigBin, DataBin, ContextBin};
                      _ ->
                          {invoke, FunctionNameBin, PythonExpressionBin, ConfigBin, Arguments}
                  end,
        Result = beamparticle_python_server:call(Command, TimeoutMsec),
        lager:debug("Result = ~p", [Result]),
        extract_logs(Result)
    catch
        C:E ->
            lager:error("error compiling Python ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end.

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(PythonExpression) when is_binary(PythonExpression)
    orelse is_list(PythonExpression) ->
    undefined.

-spec validate_python_function(binary(), string() | binary())
        -> {ok, Arity :: integer()} | {error, term()}.
validate_python_function(FunctionNameBin, PythonExpression) when is_list(PythonExpression) ->
    validate_python_function(FunctionNameBin, list_to_binary(PythonExpression));
validate_python_function(FunctionNameBin, PythonExpression)
  when is_binary(PythonExpression) andalso is_binary(FunctionNameBin) ->
    lager:debug("FunctionNameBin = ~p, PythonExpression = ~p", [FunctionNameBin, PythonExpression]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME

        RealFunctionNameBin = case FunctionNameBin of
                                  <<"__simple_http_", Rest/binary>> ->
                                      Rest;
                                  _ ->
                                      FunctionNameBin
                              end,
        Result = beamparticle_python_server:call(
                   {load, RealFunctionNameBin, PythonExpression, <<"{}">>},
                   TimeoutMsec),
        extract_logs(Result)
    catch
        C:E ->
            lager:error("error compiling Python ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end.

extract_logs({R, {log, Stdout, Stderr}}) ->
    B = case erlang:get(?LOG_ENV_KEY) of
            undefined -> {{0, []}, {0, []}};
            A -> A
        end,
    {{OldStdoutLen, OldStdout}, {OldStderrLen, OldStderr}} = B,
    %% The logs are always reverse (that is latest on the top),
    %% which is primarily done to save time in inserting
    %% them at the top.
    {UpdatedStdoutLen, UpdatedStdout} =
    case OldStdoutLen of
        _ when OldStdoutLen < ?MAX_LOG_EVENTS ->
            case is_list(Stdout) of
                false ->
                    {OldStdoutLen + 1,
                     [Stdout | OldStdout]};
                true ->
                    {OldStdoutLen + length(Stdout),
                     lists:reverse(Stdout) ++ OldStdout}
            end;
        _ ->
            case OldStdout of
                [<<"...">> | _] ->
                    {OldStdoutLen, OldStdout};
                _ ->
                    {OldStdoutLen + 1, [<<"...">> | OldStdout]}
            end
    end,
    {UpdatedStderrLen, UpdatedStderr} =
    case OldStderrLen of
        _ when OldStderrLen < ?MAX_LOG_EVENTS ->
            case is_list(Stderr) of
                false ->
                    {OldStderrLen + 1,
                     [Stderr | OldStderr]};
                true ->
                    {OldStderrLen + length(Stderr),
                     lists:reverse(Stderr) ++ OldStderr}
            end;
        _ ->
            case OldStderr of
                [<<"...">> | _] ->
                    {OldStderrLen, OldStderr};
                _ ->
                    {OldStderrLen + 1, [<<"...">> | OldStderr]}
            end
    end,
    erlang:put(?LOG_ENV_KEY,
               {{UpdatedStdoutLen, UpdatedStdout},
                {UpdatedStderrLen, UpdatedStderr}}),
    lager:debug("Stdout=~p", [Stdout]),
    lager:debug("Stderr=~p", [Stderr]),
    R;
extract_logs(Result) ->
    Result.

