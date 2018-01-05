%%%-------------------------------------------------------------------
%%% @doc
%%% Supervisor for the beamparticle app. This will boot the
%%% supervision tree required for persistent application state.
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
-module(beamparticle_jinterface_sup).
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
    JavaServerSpec = [{beamparticle_java_server, {beamparticle_java_server, start_link, [Opts]},
                   permanent, 5000, worker, [beamparticle_java_server]}],
    {ok, { {one_for_one, 1000, 3600},
        JavaServerSpec}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
