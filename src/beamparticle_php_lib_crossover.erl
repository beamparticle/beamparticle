%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% @end
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
%%%-------------------------------------------------------------------
-module(beamparticle_php_lib_crossover).

%% -behaviour(ephp_func).

-include("beamparticle_constants.hrl").

-export([
    init_func/0,
    init_config/0,
    init_const/0,

    erlang_dcall/4
]).

-include_lib("ephp/include/ephp.hrl").

-spec init_func() -> ephp_func:php_function_results().
init_func() ->
    [
     %% Note that alias function name must be used to
     %% invoke the given function name
     %% {name, [{args, ephp:validation_args()}]}
     {erlang_dcall, [{alias, <<"dcall">>},
              {args, {2, 2, false, [string, array]}}]}
    ].

-spec init_config() -> ephp_func:php_config_results().
init_config() ->
    [].

-spec init_const() -> ephp_func:php_const_results().
init_const() ->
    [].

%%-spec get_classes() -> [class()].
%%get_classes() ->
%%    [].

%% @doc Invoke dynamic functions from PHP
%%
%% The following code demonstrates the example,
%% wherein the following code invokes test/2
%% with two arguments, which must be passed
%% as regular PHP array.
%%
%% ```
%% #!php
%%
%% // in order to make dynamic call to test(A, B)
%% // the following syntax is used.
%% // Notice that strings in PHP are Erlang binaries.
%% // Also, array in PHP is Erlang list
%% // and named array in PHP is Erlang map.
%% <?php
%% function main() {
%%     return dcall("test", array(1, 2));
%% }
%%
%% ?>
%%
-spec erlang_dcall(context(), line(), var_value(), var_value()) -> term() | false.

erlang_dcall(_Context, _Line, {_, DynamicFunctionName}, {_, Args})
	when is_binary(DynamicFunctionName) andalso ?IS_ARRAY(Args) ->
    lager:debug("PHP dynamic call function ~p, raw-args = ~p",
               [DynamicFunctionName, Args]),
	ArgsForErlang = beamparticle_phpparser:convert_php_to_erlang_value(Args),
    try
        lager:debug("PHP dynamic call function ~p, args = ~p",
                    [DynamicFunctionName, ArgsForErlang]),
        Result = beamparticle_erlparser:execute_dynamic_function(
                  DynamicFunctionName, ArgsForErlang),
        beamparticle_phpparser:convert_erlang_to_php_value(Result)
    catch
        C:E ?CAPTURE_STACKTRACE ->
            lager:error("php dynamic call failed, ~p:~p, stacktrace = ~p",
                        [C, E, ?GET_STACKTRACE]),
            false
    end.


