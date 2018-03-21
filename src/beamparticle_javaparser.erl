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
-module(beamparticle_javaparser).

-include("beamparticle_constants.hrl").

-export([
    evaluate_java_expression/4,
    get_erlang_parsed_expressions/1,
    validate_java_function/2
]).

%% @doc Evaluate a given Java expression and give back result.
%%
%% IMPORTANT: "#!java" is header marker
%%
%% Sample JavaExpression
%% ```
%% #!java
%% // a sample java logic via anonymous class
%% () -> new object(){ public int main() { return 1; } }
%% '''
%%
%% Another JavaExpression
%% ```
%% #!java
%% // return Erlang atom ok always
%% import com.ericsson.otp.erlang.OtpErlangAtom;
%%
%% () -> new Object(){
%%     public OtpErlangAtom main(){
%%         return new OtpErlangAtom("ok");
%%     }
%% }
%% '''
-spec evaluate_java_expression(binary() | undefined, string() | binary(),
                              string() | binary(), [term()]) -> any().
evaluate_java_expression(FunctionNameBin, JavaExpression, Config, Arguments) when is_list(JavaExpression) ->
    JavaExpressionBin = list_to_binary(JavaExpression),
    evaluate_java_expression(FunctionNameBin, JavaExpressionBin, Config, Arguments);
evaluate_java_expression(undefined, JavaExpressionBin, _Config, []) ->
    %% TODO use Config
    lager:debug("FunctionNameBin = ~p, JavaExpressionBin = ~p, Arguments = ~p",
                [undefined, JavaExpressionBin, []]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME
        Result = beamparticle_java_server:call({eval, JavaExpressionBin},
                                                 TimeoutMsec),
        lager:debug("Result = ~p", [Result]),
        Result
    catch
        C:E ->
            lager:error("error compiling Java ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end;
evaluate_java_expression(FunctionNameBin, JavaExpressionBin, ConfigBin, Arguments) when is_list(Arguments) ->
    %% TODO use Config
    lager:debug("FunctionNameBin = ~p, JavaExpressionBin = ~p, Arguments = ~p",
                [FunctionNameBin, JavaExpressionBin, Arguments]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME
        Command = case FunctionNameBin of
                      <<"__simple_http_", RealFunctionNameBin/binary>> ->
                          [DataBin, ContextBin] = Arguments,
                          {invoke_simple_http, RealFunctionNameBin, JavaExpressionBin, ConfigBin, DataBin, ContextBin};
                      _ ->
                          {invoke, FunctionNameBin, JavaExpressionBin, ConfigBin, Arguments}
                  end,
        Result = beamparticle_java_server:call(Command, TimeoutMsec),
        lager:debug("Result = ~p", [Result]),
        case Result of
            {R, {log, Stdout, Stderr}} ->
                erlang:put(?LOG_ENV_KEY, {Stdout, Stderr}),
                lager:info("Stdout=~p", [Stdout]),
                lager:info("Stderr=~p", [Stderr]),
                R;
            _ ->
                Result
        end
    catch
        C:E ->
            lager:error("error compiling Java ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end.

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(JavaExpression) when is_binary(JavaExpression)
    orelse is_list(JavaExpression) ->
    undefined.

-spec validate_java_function(binary(), string() | binary())
        -> {ok, Arity :: integer()} | {error, term()}.
validate_java_function(FunctionNameBin, JavaExpression) when is_list(JavaExpression) ->
    validate_java_function(FunctionNameBin, list_to_binary(JavaExpression));
validate_java_function(FunctionNameBin, JavaExpression)
  when is_binary(JavaExpression) andalso is_binary(FunctionNameBin) ->
    lager:debug("FunctionNameBin = ~p, JavaExpression = ~p", [FunctionNameBin, JavaExpression]),
    try
        TimeoutMsec = 5 * 60 * 1000, %% default timeout is 5 minutes TODO FIXME
        RealFunctionNameBin = case FunctionNameBin of
                                  <<"__simple_http_", Rest/binary>> ->
                                      Rest;
                                  _ ->
                                      FunctionNameBin
                              end,
        beamparticle_java_server:call({load, RealFunctionNameBin, JavaExpression, <<"{}">>},
                                        TimeoutMsec)
    catch
        C:E ->
            lager:error("error compiling Java ~p:~p, stacktrace = ~p",
                        [C, E, erlang:get_stacktrace()]),
            {error, {exception, {C, E}}}
    end.


