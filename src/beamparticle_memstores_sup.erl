%%%-------------------------------------------------------------------
%%% @doc
%%% Supervisor for the beamparticle in-memory stores.
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
-module(beamparticle_memstores_sup).
-behaviour(supervisor).

-export([start_link/0]).
%% callbacks
-export([init/1]).

-include("beamparticle_constants.hrl").

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
        supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Callbacks
%%%===================================================================
init(_Args) ->
    Opts = [],
    SeqWriteStoreSpec = [{beamparticle_seq_write_store,
                          {beamparticle_seq_write_store, start_link, [Opts]},
                          permanent, 5000, worker,
                          [beamparticle_seq_write_store]}],
    FastWriteStoreSpec = [{beamparticle_fast_write_store,
                           {beamparticle_fast_write_store, start_link, [Opts]},
                           permanent, 5000, worker,
                           [beamparticle_fast_write_store]}],
    {ok, { {one_for_one, 1000, 3600},
        SeqWriteStoreSpec ++ FastWriteStoreSpec}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

