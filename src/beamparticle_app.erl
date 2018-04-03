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
-module(beamparticle_app).
-author("neerajsharma").

-behaviour(application).

-include("beamparticle_constants.hrl").

%% Application callbacks
-export([start/2,
  stop/1]).

-export([delayed_system_setup/0]).

-define(DELAYED_STARTUP_MSEC, 1000).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term()) ->
  {ok, pid()} |
  {ok, pid(), State :: term()} |
  {error, Reason :: term()}).
start(_StartType, _StartArgs) ->
  %% call wallclock time first, so that counters are reset
  %% so on subsequent calls the Total time returned by
  %% erlang:statistics(wall_clock) can be used as uptime.
  beamparticle_util:node_uptime(second),

  %% start marina when configured
  case application:get_all_env(marina) of
      [{_, []}] ->
          %% empty configuration, so do not start
          ok;
      _ ->
          application:ensure_all_started(marina)
  end,

  {ok, Caches} = application:get_env(?APPLICATION_NAME, caches),
  lists:foreach(fun({CacheName, CacheOptions}) ->
      beamparticle_cache_util:cache_start_link(CacheOptions, CacheName)
                end, Caches),

  %% setup ephp because otherwise php functions are not available
  ephp:start(),

  %% setup erlcloud
  ErlCloudOptions = application:get_env(?APPLICATION_NAME, erlcloud, []),
  lists:foreach(fun({E, V}) ->
                        application:set_env(erlcloud, E, V)
                end, ErlCloudOptions),

  % TODO only when running in production
  PrivDir = code:priv_dir(?APPLICATION_NAME),
  %PrivDir = "priv",
  lager:debug("detected PrivDir=~p", [PrivDir]),
  Port = application:get_env(?APPLICATION_NAME, port, ?DEFAULT_HTTP_PORT),

    HttpRestConfig = application:get_env(?APPLICATION_NAME, http_rest, []),
    start_http_server(PrivDir, Port, HttpRestConfig),

    HttpNLPRestConfig = application:get_env(?APPLICATION_NAME, http_nlp_rest, []),
    start_http_nlp_server(HttpNLPRestConfig),

    HighPerfHttpRestConfig = application:get_env(
                               ?APPLICATION_NAME,
                               highperf_http_rest, []),
    start_highperf_http_server(HighPerfHttpRestConfig),
 
    %% start opentrace server if enabled
    OpenTracingServerConfig = application:get_env(?APPLICATION_NAME, opentracing_server, []),
    IsOpenTracingServerEnabled =
        proplists:get_value(enable, OpenTracingServerConfig, false),
    case IsOpenTracingServerEnabled of
        true ->
            {ok, _OpentracingPid} =
                start_opentrace_server(OpenTracingServerConfig);
        false ->
            ok
    end,

  %% TODO onresponse will no longer work.
  %% see https://github.com/foxford/datastore/blob/master/src/datastore_streamh_log.erl?ts=2
  %% https://github.com/foxford/datastore/blob/master/src/datastore_http.erl?ts=2#L62
  %% https://github.com/ninenines/cowboy/issues/1036 (end)

  LevelDbConfig = application:get_env(?APPLICATION_NAME, leveldb_config, []),
  LevelDbActors = [Name || {Name, _} <- LevelDbConfig],
  {ok, _} = timer:apply_after(?DELAYED_STARTUP_MSEC,
                              ?MODULE, delayed_system_setup, []),
  %% start smtp server not required because
  %% beamparticle_sup:start_link/1 takes care of starting the
  %% gen_smtp_server worker with beamparticle_smtp_server module and other options
  %%gen_smtp_server:start(beamparticle_smtp_server, [[{protocol, plain}, {port, 25}]]),
  beamparticle_sup:start_link(LevelDbActors).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

delayed_system_setup() ->
    %% start python nodes when enabled
    PynodeConfig = application:get_env(?APPLICATION_NAME, pynode, []),
    case proplists:get_value(enable, PynodeConfig, false) of
        true ->
            PynodeNumWorkers = proplists:get_value(num_workers,
                                                   PynodeConfig, 1),
            PynodeShutdownDelayMsec = proplists:get_value(shutdown_delay_msec,
                                                          PynodeConfig,
                                                          10000),
            PynodeMinAliveRatio = proplists:get_value(min_alive_ratio,
                                                      PynodeConfig,
                                                      1.0),
            PynodeReconnectDelayMsec = proplists:get_value(reconnect_delay_msec,
                                                           PynodeConfig,
                                                           500),
            beamparticle_python_server:create_pool(
              PynodeNumWorkers, PynodeShutdownDelayMsec,
              PynodeMinAliveRatio, PynodeReconnectDelayMsec);
        false ->
            ok
    end,
    %% start java nodes when enabled
    JavanodeConfig = application:get_env(?APPLICATION_NAME, javanode, []),
    case proplists:get_value(enable, JavanodeConfig, false) of
        true ->
            JavanodeNumWorkers = proplists:get_value(num_workers,
                                                     JavanodeConfig, 1),
            JavanodeShutdownDelayMsec = proplists:get_value(shutdown_delay_msec,
                                                            JavanodeConfig,
                                                            10000),
            JavanodeMinAliveRatio = proplists:get_value(min_alive_ratio,
                                                        JavanodeConfig,
                                                        1.0),
            JavanodeReconnectDelayMsec = proplists:get_value(reconnect_delay_msec,
                                                             JavanodeConfig,
                                                             500),
            beamparticle_java_server:create_pool(
              JavanodeNumWorkers, JavanodeShutdownDelayMsec,
              JavanodeMinAliveRatio, JavanodeReconnectDelayMsec);
        false ->
            ok
    end,
    %% start palma pools
    {ok, PalmaPools} = application:get_env(?APPLICATION_NAME, palma_pools),
    % all the pools must start
    PalmaPoolStartResult = lists:foldl(fun(E, AccIn) ->
        {PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions} = E,
        lager:info("Starting PalmaPool = ~p", [E]),
        case palma:new(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions) of
            {ok, _} -> AccIn;
            Error2 -> [{Error2, E} | AccIn]
        end
                 end, [], PalmaPools),
    [] = PalmaPoolStartResult,
    %% load crons stored on disk
    beamparticle_jobs:load(),
    beamparticle_pools:load(),
    %% start reaching out to peer nodes
    ClusterConfig = application:get_env(?APPLICATION_NAME, cluster, []),
    PeerNodes = proplists:get_value(peers, ClusterConfig, []),
    lists:foreach(fun(E) ->
                          net_adm:ping(E)
                  end, PeerNodes),
    ok.

start_opentrace_server(OpenTracingServerConfig) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/api/v1/spans", beamparticle_zipkin_handler, []}
            %% {"/[...]", beamparticle_zipkin_handler, []}
        ]}
    ]),
    Port = proplists:get_value(port, OpenTracingServerConfig, 9411),
    NumAcceptors = proplists:get_value(
                     num_acceptors, OpenTracingServerConfig, 10),
    MaxConnections = proplists:get_value(
                       max_connections, OpenTracingServerConfig, 1000),
    Backlog = proplists:get_value(
                backlog, OpenTracingServerConfig, 1024),
    cowboy:start_clear(opentrace_http, [
	    {port, Port},
	    {num_acceptors, NumAcceptors},
	    {backlog, Backlog},
	    {max_connections, MaxConnections}],
	    #{env => #{dispatch => Dispatch} }).


start_http_server(PrivDir, Port, HttpRestConfig) ->
   Dispatch = cowboy_router:compile([
      {'_', [
        %%{"/", cowboy_static, {priv_file, beamparticle, "index.html"}},
        {"/static/[...]", cowboy_static, {dir, PrivDir ++ "/static"}},
        {"/", cowboy_static, {file, PrivDir ++ "/index.html"}},
        {"/dev", cowboy_static, {file, PrivDir ++ "/index-dev.html"}},
        {"/auth/google/[...]", beamparticle_google_oauth_handler, []},
        {"/fun/[:id]", beamparticle_generic_handler, [beamparticle_dynamic_function_model]},
        %% /post is now depricated, instead use /api/[:id] with POST
        {"/post/[:id]", beamparticle_generic_handler, [beamparticle_simple_http_post_model]},
        {"/api/[:id]", beamparticle_generic_handler, [beamparticle_simple_http_post_model]},
        {"/voice", cowboy_static, {file, PrivDir ++ "/voice.html"}},
        %% {"/rule/[:id]", beamparticle_generic_handler, [beamparticle_k_model]},
        {"/ws", beamparticle_ws_handler, []}
      ]}
    ]),
    NrListeners = proplists:get_value(nr_listeners,
                                      HttpRestConfig,
                                      ?DEFAULT_HTTP_NR_LISTENERS),
    Backlog = proplists:get_value(backlog,
                                  HttpRestConfig,
                                  ?DEFAULT_HTTP_BACKLOG),
    MaxConnections = proplists:get_value(max_connections,
                                         HttpRestConfig,
                                         ?DEFAULT_HTTP_MAX_CONNECTIONS),
    %% Important: max_keepalive is only available in cowboy 2
    MaxKeepAlive = proplists:get_value(max_keepalive,
                                       HttpRestConfig,
                                       ?DEFAULT_MAX_HTTP_KEEPALIVES),
    IsSsl = proplists:get_value(ssl, HttpRestConfig,
                                ?DEFAULT_HTTP_IS_SSL_ENABLED),
    case IsSsl of
        true ->
            {ok, _} = cowboy:start_tls(https, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections},
                %% {cacertfile, PrivDir ++ "/ssl/ca-chain.cert.pem"},
                {certfile, PrivDir ++ "/ssl/cert.pem"},
                {keyfile, PrivDir ++ "/ssl/key.pem"},
                {versions, ['tlsv1.2']},
                {ciphers, ["ECDHE-ECDSA-AES256-GCM-SHA384","ECDHE-RSA-AES256-GCM-SHA384",
                    "ECDHE-ECDSA-AES256-SHA384","ECDHE-RSA-AES256-SHA384", "ECDHE-ECDSA-DES-CBC3-SHA",
                    "ECDH-ECDSA-AES256-GCM-SHA384","ECDH-RSA-AES256-GCM-SHA384","ECDH-ECDSA-AES256-SHA384",
                    "ECDH-RSA-AES256-SHA384","DHE-DSS-AES256-GCM-SHA384","DHE-DSS-AES256-SHA256",
                    "AES256-GCM-SHA384","AES256-SHA256","ECDHE-ECDSA-AES128-GCM-SHA256",
                    "ECDHE-RSA-AES128-GCM-SHA256","ECDHE-ECDSA-AES128-SHA256","ECDHE-RSA-AES128-SHA256",
                    "ECDH-ECDSA-AES128-GCM-SHA256","ECDH-RSA-AES128-GCM-SHA256","ECDH-ECDSA-AES128-SHA256",
                    "ECDH-RSA-AES128-SHA256","DHE-DSS-AES128-GCM-SHA256","DHE-DSS-AES128-SHA256",
                    "AES128-GCM-SHA256","AES128-SHA256","ECDHE-ECDSA-AES256-SHA",
                    "ECDHE-RSA-AES256-SHA","DHE-DSS-AES256-SHA","ECDH-ECDSA-AES256-SHA",
                    "ECDH-RSA-AES256-SHA","AES256-SHA","ECDHE-ECDSA-AES128-SHA",
                    "ECDHE-RSA-AES128-SHA","DHE-DSS-AES128-SHA","ECDH-ECDSA-AES128-SHA",
                    "ECDH-RSA-AES128-SHA","AES128-SHA"]}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  onresponse => fun log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive});
        false ->
            {ok, _} = cowboy:start_clear(http, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  onresponse => fun log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive})
    end.

start_http_nlp_server([]) ->
    ok;
start_http_nlp_server(HttpNLPRestConfig) ->
    PrivDir = code:priv_dir(?APPLICATION_NAME),
    Port = proplists:get_value(port, HttpNLPRestConfig,
                               ?DEFAULT_HIGHPERF_HTTP_PORT),
    Dispatch = cowboy_router:compile([
      {'_', [
        %%{"/", cowboy_static, {priv_file, beamparticle, "index.html"}},
        {"/static/[...]", cowboy_static, {dir, PrivDir ++ "/static"}},
        {"/dev", cowboy_static, {file, PrivDir ++ "/index-dev.html"}},
        {"/", beamparticle_nlp_top_page_handler, []},
        {"/auth/google/[...]", beamparticle_google_oauth_handler, []},
        %% /post is now depricated, instead use /api/[:id] with POST
        {"/post/[:id]", beamparticle_generic_handler, [beamparticle_simple_http_post_model]},
        {"/api/[:id]", beamparticle_generic_handler, [beamparticle_simple_http_post_model]},
        {"/ws", beamparticle_nlp_ws_handler, []}
      ]}
    ]),
    NrListeners = proplists:get_value(nr_listeners,
                                      HttpNLPRestConfig,
                                      ?DEFAULT_HTTP_NR_LISTENERS),
    Backlog = proplists:get_value(backlog,
                                  HttpNLPRestConfig,
                                  ?DEFAULT_HTTP_BACKLOG),
    MaxConnections = proplists:get_value(max_connections,
                                         HttpNLPRestConfig,
                                         ?DEFAULT_HTTP_MAX_CONNECTIONS),
    %% Important: max_keepalive is only available in cowboy 2
    MaxKeepAlive = proplists:get_value(max_keepalive,
                                       HttpNLPRestConfig,
                                       ?DEFAULT_MAX_HTTP_KEEPALIVES),
    IsSsl = proplists:get_value(ssl, HttpNLPRestConfig,
                                ?DEFAULT_HTTP_IS_SSL_ENABLED),
    case IsSsl of
        true ->
            {ok, _} = cowboy:start_tls(nr_https, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections},
                %% {cacertfile, PrivDir ++ "/ssl/ca-chain.cert.pem"},
                {certfile, PrivDir ++ "/ssl/cert.pem"},
                {keyfile, PrivDir ++ "/ssl/key.pem"},
                {versions, ['tlsv1.2']},
                {ciphers, ["ECDHE-ECDSA-AES256-GCM-SHA384","ECDHE-RSA-AES256-GCM-SHA384",
                    "ECDHE-ECDSA-AES256-SHA384","ECDHE-RSA-AES256-SHA384", "ECDHE-ECDSA-DES-CBC3-SHA",
                    "ECDH-ECDSA-AES256-GCM-SHA384","ECDH-RSA-AES256-GCM-SHA384","ECDH-ECDSA-AES256-SHA384",
                    "ECDH-RSA-AES256-SHA384","DHE-DSS-AES256-GCM-SHA384","DHE-DSS-AES256-SHA256",
                    "AES256-GCM-SHA384","AES256-SHA256","ECDHE-ECDSA-AES128-GCM-SHA256",
                    "ECDHE-RSA-AES128-GCM-SHA256","ECDHE-ECDSA-AES128-SHA256","ECDHE-RSA-AES128-SHA256",
                    "ECDH-ECDSA-AES128-GCM-SHA256","ECDH-RSA-AES128-GCM-SHA256","ECDH-ECDSA-AES128-SHA256",
                    "ECDH-RSA-AES128-SHA256","DHE-DSS-AES128-GCM-SHA256","DHE-DSS-AES128-SHA256",
                    "AES128-GCM-SHA256","AES128-SHA256","ECDHE-ECDSA-AES256-SHA",
                    "ECDHE-RSA-AES256-SHA","DHE-DSS-AES256-SHA","ECDH-ECDSA-AES256-SHA",
                    "ECDH-RSA-AES256-SHA","AES256-SHA","ECDHE-ECDSA-AES128-SHA",
                    "ECDHE-RSA-AES128-SHA","DHE-DSS-AES128-SHA","ECDH-ECDSA-AES128-SHA",
                    "ECDH-RSA-AES128-SHA","AES128-SHA"]}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  onresponse => fun log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive});
        false ->
            {ok, _} = cowboy:start_clear(nr_http, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  onresponse => fun log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive})
    end.

start_highperf_http_server(HighPerfHttpRestConfig) ->
    Port = proplists:get_value(port, HighPerfHttpRestConfig,
                               ?DEFAULT_HIGHPERF_HTTP_PORT),
    NrListeners = proplists:get_value(nr_listeners,
                                      HighPerfHttpRestConfig,
                                      ?DEFAULT_HTTP_NR_LISTENERS),
    TransportOpts = [{port, Port},
                     {num_acceptors, NrListeners}],
    ProtocolOpts = HighPerfHttpRestConfig,
    {ok, _} = ranch:start_listener(highperf_http_server,
                                   ranch_tcp, TransportOpts,
                                   beamparticle_highperf_http_handler,
                                   ProtocolOpts).
