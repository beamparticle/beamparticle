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
-module(beamparticle_sup).
-behaviour(supervisor).

-export([start_link/1]).
%% callbacks
-export([init/1]).

-include("beamparticle_constants.hrl").

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link([module()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Models) ->
        supervisor:start_link({local, ?SERVER}, ?MODULE, Models).

%%%===================================================================
%%% Callbacks
%%%===================================================================
init(Specs) ->
    MemStoresSupSpec = [{beamparticle_memstores_sup,
                         {beamparticle_memstores_sup, start_link, []},
                         permanent, 5000, supervisor,
                         [beamparticle_memstores_sup]}],
    EcrnSupSpec = [{ecrn_sup, {ecrn_sup, start_link, []},
                   permanent, 5000, supervisor, [ecrn_sup]}],
    WorkerSpecs = [{Name,
        {?STORE_MODULE, start_link, [Name]},
        permanent, 5000, worker, [?STORE_MODULE]}
        || Name <- Specs],
    MemstoreSpec = [{memstore_proc, {memstore_proc, start_link, [memstore_proc]},
                     permanent, 5000, worker, [memstore_proc]}],
    ClusterMonitorSpec = [{beamparticle_cluster_monitor,
                           {beamparticle_cluster_monitor, start_link, [ [] ]},
                           permanent, 5000, worker, [beamparticle_cluster_monitor]}],
    %% start smtp server
    SmtpConfig = application:get_env(?APPLICATION_NAME, smtp, []),
    SmtpSpec = case proplists:get_value(enable, SmtpConfig, false) of
                   true ->
                       SmtpDomain = proplists:get_value(domain, SmtpConfig),
                       SmtpServerName = beamparticle_smtp_server,
                       SmtpServerConfig1 = [{protocol, tcp},
                                            {port, 25},
                                            {domain, SmtpDomain},
                                            {address,{0,0,0,0}},
                                            {sessionoptions,
                                             [{allow_bare_newlines, fix},
                                              {callbackoptions,
                                               [{parse, true}]}]}],
                       NewtonSmtpServerArgs = [SmtpServerConfig1],
                       GenSmtpServerArgList = [{'local', SmtpServerName},
                                               beamparticle_smtp_server,
                                               NewtonSmtpServerArgs],
                       [{SmtpServerName, {gen_smtp_server, start_link,
                                              GenSmtpServerArgList},
                         permanent, 5000, worker, [SmtpServerName]}];
                   false ->
                       []
               end,
    JinterfaceSupSpec = [{beamparticle_jinterface_sup,
                          {beamparticle_jinterface_sup, start_link, []},
                          permanent, 5000, supervisor, [beamparticle_jinterface_sup]}],
    {ok, { {one_for_one, 1000, 3600},
        MemStoresSupSpec ++
        ClusterMonitorSpec ++ MemstoreSpec ++ SmtpSpec ++
        EcrnSupSpec ++ WorkerSpecs}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
