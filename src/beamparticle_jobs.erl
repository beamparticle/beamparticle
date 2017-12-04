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
-module(beamparticle_jobs).


-export([load/0, add/3, add/4, delete/1, all/0, get_details/1]).

%% @doc Load cron from disk
-spec load() -> ok.
load() ->
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, job) of
                     undefined ->
                         throw({{ok, R}, S2});
                     ExtractedKey ->
                         {[{ExtractedKey, V} | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, <<>>, job),
    lists:foreach(fun({K,V}) ->
                          JobDetails = sext:decode(V),
                          erlcron:cron(JobDetails, K)
                  end, Resp),
    ok.

%% @doc Add a new cron
%% as an example JobSpecScheduleOnly is {monthly, 1, {2, am}}
-spec add(tuple(), binary(), list()) -> binary().
add(JobSpecScheduleOnly, FunctionName, Arguments) ->
    add(JobSpecScheduleOnly, FunctionName, Arguments, false).

%% @doc Add a new cron
%% as an example JobSpecScheduleOnly is {monthly, 1, {2, am}}
-spec add(tuple(), binary(), list(), boolean()) -> binary().
add(JobSpecScheduleOnly, FunctionName, Arguments, Persist) when is_boolean(Persist) ->
    JobSpec = {JobSpecScheduleOnly, {beamparticle_dynamic, execute, [{FunctionName, Arguments}]}},
    lager:info("add JobSpec = ~p", [JobSpec]),
    JobRefCreated = erlcron:cron(JobSpec),
    case Persist of
        true ->
            JobSpecBin = sext:encode(JobSpec),
            beamparticle_storage_util:write(JobRefCreated, JobSpecBin, job);
        false ->
            ok
    end,
    JobRefCreated.

delete(JobRef) ->
    beamparticle_storage_util:delete(JobRef, job),
    erlcron:cancel(JobRef).


%% @doc get all the job references
-spec all() -> [binary()].
all() ->
    %% same thing you can ask from beamparticle_storage_util as well.
    lists:foldl(fun({Ref, _EcrnAgentPid}, AccIn) ->
                        [Ref | AccIn]
                end, [], ecrn_reg:get_all()).

%% @doc get job details
-spec get_details(binary()) -> {tuple(), binary(), list()}.
get_details(JobRef) ->
    V = beamparticle_storage_util:read(JobRef, job),
    JobDetails = sext:decode(V),
    {JobSpecScheduleOnly, {_M, _F, [{FunctionName, Arguments}]}} =
        JobDetails,
    {JobSpecScheduleOnly, FunctionName, Arguments}.

