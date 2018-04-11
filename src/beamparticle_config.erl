%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% @end
%%%
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
-module(beamparticle_config).

-export([save_to_production/0,
         is_function_allowed/2]).

-include("beamparticle_constants.hrl").

-spec save_to_production() -> boolean().
save_to_production() ->
    CodeConfig = application:get_env(?APPLICATION_NAME, code, []),
    case proplists:get_value(save_to_production, CodeConfig, true) of
        true ->
            true;
        _ ->
            false
    end.

-spec is_function_allowed(binary(), http_rest | highperf_http_rest) -> boolean().
is_function_allowed(FunctionName, SectionName) ->
    HttpConfig = application:get_env(?APPLICATION_NAME, SectionName, []),
    case proplists:get_value(allowed_dynamic_functions, HttpConfig, undefined) of
        undefined ->
            true;
        [] ->
            false;
        AllowedDynamicFunctions ->
            %% TODO: This is very expensive when allowed functions are a lot more
            lists:member(FunctionName, AllowedDynamicFunctions)
    end.
