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
-module(beamparticle_pools).


-export([load/0, add_worker/5, add/5, add/6, delete/1, all/0, get_details/1]).

%% @doc Load cron from disk
-spec load() -> ok.
load() ->
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, pool) of
                     undefined ->
                         throw({{ok, R}, S2});
                     ExtractedKey ->
                         {[{ExtractedKey, V} | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, <<>>, pool),
    lists:foreach(fun({_PoolNameBin, V}) ->
                          PoolDetails = sext:decode(V),
                          lager:info("Starting PalmaPool = ~p", [PoolDetails]),
                          {PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions} = PoolDetails,
                          case palma:new(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions) of
                              {ok, _} ->
                                  ok;
                              Error2 ->
                                  {Error2, PoolDetails}
                          end
                  end, Resp),
    ok.

add_worker(PoolName, PoolSize, PoolWorkerId, FunctionNameBin, FunctionArguments) ->
    PoolChildSpec = {PoolWorkerId, {
                      beamparticle_generic_pool_worker,
                      start_link,
                      [
                       [FunctionNameBin | FunctionArguments]
                      ]},
                     {permanent, 5},  %% see palma_supervisor2
                     1000,  %% milli seconds to wait before killing
                     worker,  %% it is a worker (and not supervisor)
                     [beamparticle_generic_pool_worker]
                    },
    ShutdownDelayMsec = 10000,
    RevolverOptions = #{ min_alive_ratio => 1.0, reconnect_delay => 5000},
    add(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions).

%% @doc Add a new pool
-spec add(atom(), integer(), tuple(), integer(), map()) -> binary().
add(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions) ->
    add(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions, false).

%% @doc Add a new pool
-spec add(atom(), integer(), tuple(), integer(), map(), boolean()) -> binary().
add(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions, Persist) when is_boolean(Persist) ->
    PoolDetails = {PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions},
    lager:info("Starting PalmaPool = ~p", [PoolDetails]),
    {ok, _} = palma:new(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions),
    PoolNameBin = atom_to_binary(PoolName, utf8),
    case Persist of
        true ->
            PoolDetailsBin = sext:encode(PoolDetails),
            beamparticle_storage_util:write(PoolNameBin, PoolDetailsBin, pool);
        false ->
            ok
    end,
    PoolNameBin.

delete(PoolNameBin) when is_binary(PoolNameBin) ->
    case beamparticle_storage_util:read(PoolNameBin, pool) of
        {ok, V} ->
            PoolDetails = sext:decode(V),
            {PoolName, _PoolSize, _PoolChildSpec, _ShutdownDelayMsec, _RevolverOptions} = PoolDetails,
            beamparticle_storage_util:delete(PoolNameBin, pool),
            palma:stop(PoolName);
        _ ->
            ok
    end.

%% @doc get all the pool references
-spec all() -> [binary()].
all() ->
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, pool) of
                     undefined ->
                         throw({{ok, R}, S2});
                     _ExtractedKey ->
                         {[V | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, <<>>, pool),
    Resp.

%% @doc get pool details
-spec get_details(binary()) -> term().
get_details(PoolNameBin) ->
    case beamparticle_storage_util:read(PoolNameBin, pool) of
        {ok, V} ->
            %% {PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions} = PoolDetails
            sext:decode(V);
        _ ->
            {error, not_found}
    end.
