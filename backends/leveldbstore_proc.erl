%%%-------------------------------------------------------------------
%%% @doc
%%% The general architecture of a singular process per base REST API
%%% will lead to a lot of messages into this process. This has the
%%% benefit of sequential operation thereby making it easy for features
%%% like key expiry to be implemented, but do not allow simultaneous
%%% read/writes on the backend.
%%%
%%% An alternative strategy, would be for this process would be to
%%% change leveldbstore use eleveldb async calls and keep references
%%% of callers rather than blocking each message and reply sequentially.
%%% This will allow usage of eleveldb backend to the maximum, where its
%%% underlying threads will be forced to work in parallel. Having said
%%% that when key partition is done then the mentioned parallelism could
%%% be an overhead although this needs more research and detailed
%%% analysis to be correctly implemented.
%%%
%%% @end
%%% Copyright (c) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>.
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are
%%% met:
%%%
%%% * Redistributions of source code must retain the above copyright
%%%   notice, this list of conditions and the following disclaimer.
%%%
%%% * Redistributions in binary form must reproduce the above copyright
%%%   notice, this list of conditions and the following disclaimer in the
%%%   documentation and/or other materials provided with the distribution.
%%%
%%% * The names of its contributors may not be used to endorse or promote
%%%   products derived from this software without specific prior written
%%%   permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%%% A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%%% OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
%%% LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
%%% DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
%%% THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%%-------------------------------------------------------------------

-module(leveldbstore_proc).
-behaviour(gen_server).
-export([get_pid/1]).
-export([start_link/1,
         start_link/2,
         create/4, read/3, update/4, delete/3, lapply/4,
         reset/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3, terminate/2]).

-ignore_xref([start_link/1, reset/1]).

-include("beamparticle_constants.hrl").

-type name() :: atom().
-type key() :: term().
-type val() :: term().
-type state() :: term().

%%%===================================================================
%%% PUBLIC API
%%%===================================================================
-spec get_pid(Poolname :: atom()) -> pid() | {error, disconnected}.
get_pid(Poolname) ->
    palma:pid(Poolname).

-spec start_link(atom()) -> {ok, pid()}.
start_link(Name) ->
    gen_server:start_link({local,Name}, ?MODULE, [Name], []).

-spec start_link(dbowner, atom()) -> {ok, pid()}.
start_link(dbowner, DbOwnerProcName) ->
    gen_server:start_link(?MODULE, [dbowner, DbOwnerProcName], []).

-spec create(name(), key(), val(), state()) -> boolean().
create(Name, K, V, nostate) ->
    gen_server:call(Name, {create, K, V});
create(_Name, K, V, State) ->
    {ok, _} = leveldbstore:create(K, V, State),
    true.

-spec read(name(), key(), state()) ->
        {ok, term()} | {error, not_found}.
read(Name, K, nostate) ->
    gen_server:call(Name, {read, K});
read(_Name, K, State) ->
    {Resp, _} = leveldbstore:read(K, State),
    Resp.

-spec update(name(), key(), val(), state()) -> boolean().
update(Name, K, V, nostate) ->
    gen_server:call(Name, {update, K, V});
update(_Name, K, V, State) ->
    {ok, _} = leveldbstore:update(K, V, State),
    true.

-spec delete(name(), key(), state()) -> boolean().
delete(Name, K, nostate) ->
    gen_server:call(Name, {delete, K});
delete(_Name, K, State) ->
    {_Resp, _} = leveldbstore:delete(K, State),
    true.

-spec lapply(name(),
            fun(({binary(), binary()}, {term(), state()}) -> term()),
            binary(), state()) -> {ok, term()} | {error, term()}.
lapply(Name, Fun, KeyPrefix, nostate) ->
    gen_server:call(Name, {lapply, Fun, KeyPrefix});
lapply(_Name, Fun, KeyPrefix, State) ->
    {Resp, _State2} = leveldbstore:lapply(Fun, KeyPrefix, State),
    Resp.

%% @private clears the leveldbstore data -- useful for tests.
reset(Name) ->
    gen_server:call(Name, reset).

%%%===================================================================
%%% GEN_SERVER CALLBACKS
%%%===================================================================
init([Name]) ->
    %% raise priority to high (out of low, normal, high, and max)
    %% so that it is getting more cpu slice
    process_flag(priority, high),
    {ok, LeveldbConfig} = application:get_env(?APPLICATION_NAME, leveldb_config),
    MyConfig = proplists:get_value(Name, LeveldbConfig),
    DbPath = proplists:get_value(dbpath, MyConfig),
    DbOptions = proplists:get_value(dboptions, MyConfig),
    TimeoutMsec = proplists:get_value(timeout_msec, MyConfig, ?DEFAULT_KEYEXPIRY_COLLECTOR_TIMEOUT_MSEC),
    State = leveldbstore:init([DbPath, DbOptions, TimeoutMsec]),
    {ok, State};
init([dbowner, DbOwnerProcName]) ->
    %% raise priority to high (out of low, normal, high, and max)
    %% so that it is getting more cpu slice
    process_flag(priority, high),
    %% get state from dbowner and use as its own
    {ok, State} = gen_server:call(DbOwnerProcName, {get_state}),
    lager:debug("[~p] Using state=~p from ~p", [self(), State, DbOwnerProcName]),
    {ok, State}.

handle_call({get_state}, _From, State) ->
    {reply, {ok, State}, State};
handle_call({create, K, V}, _From, State) ->
    {ok, State2} = leveldbstore:create(K, V, State),
    {reply, true, State2};
handle_call({read, K}, _From, State) ->
    {Resp, State2} = leveldbstore:read(K, State),
    {reply, Resp, State2};
handle_call({update, K, V}, _From, State) ->
    {ok, State2} = leveldbstore:update(K, V, State),
    {reply, true, State2};
handle_call({delete, K}, _From, State) ->
    {_Resp, State2} = leveldbstore:delete(K, State),
    % let delete be always successful irrespective
    % of whether it existed in the first place.
    {reply, true, State2};
handle_call({lapply, Fun, KeyPrefix}, _From, State) ->
    {Resp, State2} = leveldbstore:lapply(Fun, KeyPrefix, State),
    {reply, Resp, State2};
handle_call(reset, _From, State) ->
    leveldbstore:dropall(State),
    {reply, ok, State}.

handle_cast(mark_and_sweep, State) ->
    ok = leveldbstore:delete_expired_keys(State),
    {noreply, State};
handle_cast({create, K, V}, State) ->
    %% never fail
    {_, State2} = leveldbstore:create(K, V, State),
    {noreply, State2};
handle_cast({update, K, V}, State) ->
    %% never fail
    {_, State2} = leveldbstore:update(K, V, State),
    {noreply, State2};
handle_cast({delete, K}, State) ->
    %% never fail
    {_Resp, State2} = leveldbstore:delete(K, State),
    % let delete be always successful irrespective
    % of whether it existed in the first place.
    {noreply, State2};
handle_cast({lapply, Fun, KeyPrefix}, State) ->
    {_Resp, State2} = leveldbstore:lapply(Fun, KeyPrefix, State),
    {noreply, State2};
handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_, State) ->
    leveldbstore:terminate(State).
