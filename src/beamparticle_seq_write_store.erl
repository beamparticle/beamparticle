%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% This is an in-memory key value store, which is allows simultaneous
%%% read, but write or delete are sequentialized. This can have some
%%% useful properties in lieu of fast writes. This functioality can be
%%% changed easily, but at present there is no such requirement hence
%%% why bother. Additionally, avoid write concurrency help reduce the
%%% memory footprint considerably hence this initial choice.
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
-module(beamparticle_seq_write_store).
-behaviour(gen_server).

-include("beamparticle_constants.hrl").

%% API
-export([start_link/1]).
-export([call/2, cast/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

%% API
-export([create/2,
         create_async/2,
         create_or_update/2,
         create_or_update_async/2,
         read/1,
         update/2,
         update_async/2,
         delete/1,
         delete_async/1]).

-type key() :: term().
-type val() :: term().

-define(SERVER, ?MODULE).

-define(SEQ_WRITE_STORE, seq_write_ets_table).

-record(state, {
          tbl  %% ets table
         }).

%%%===================================================================
%%% API
%%%===================================================================

-spec create(key(), val()) -> boolean() | {error, disconnected}.
create(K, V) ->
    ?MODULE:call({create, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

-spec create_async(key(), val()) -> ok.
create_async(K, V) ->
    ?MODULE:cast({create, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

-spec create_or_update(key(), val()) -> boolean() | {error, disconnected}.
create_or_update(K, V) ->
    ?MODULE:call({create_or_update, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

-spec create_or_update_async(key(), val()) -> ok.
create_or_update_async(K, V) ->
    ?MODULE:cast({create_or_update, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

-spec read(key()) -> {ok, term()} | {error, not_found}.
read(K) ->
    MatchSpec = [{{K,'$1'},[],['$1']}],
    case ets:select(?SEQ_WRITE_STORE, MatchSpec) of
        [V] ->
            {ok, V};
        _ ->
            {error, not_found}
    end.

-spec update(key(), val()) -> boolean() | {error, disconnected}.
update(K, V) ->
    case ?MODULE:call({update, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC) of
        V when is_boolean(V) ->
            V;
        E ->
            E
    end.

-spec update_async(key(), val()) -> ok.
update_async(K, V) ->
    ?MODULE:cast({update, K, V}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

-spec delete(key()) -> boolean() | {error, disconnected}.
delete(K) ->
    case ?MODULE:call({delete, K}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC) of
        V when is_boolean(V) ->
            V;
        E ->
            E
    end.

-spec delete_async(key()) -> ok.
delete_async(K) ->
    ?MODULE:cast({delete, K}, ?DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Options :: list()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

%% @doc Send a sync message to the server
-spec call(Message :: term(), TimeoutMsec :: non_neg_integer() | infinity)
        -> ok | {error, disconnected}.
call(Message, TimeoutMsec) ->
    try
        gen_server:call(?SERVER, Message, TimeoutMsec)
    catch
        exit:{noproc, _} ->
            {error, disconnected}
    end.

%% @doc Send an async message to the server
-spec cast(Message :: term()) -> ok.
cast(Message) ->
    gen_server:cast(?SERVER, Message).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init(_Args) ->
    TId = ets:new(?SEQ_WRITE_STORE,
                  [set,
                   named_table,
                   protected,
                   {read_concurrency, true},
                   {write_concurrency,false},
                   {keypos, 1}
                  ]),
    {ok, #state{tbl = TId}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({create, K, V}, _From, State) ->
    R = ets:insert_new(?SEQ_WRITE_STORE, {K, V}),
    {reply, R, State};
handle_call({create_or_update, K, V}, _From, State) ->
    R = ets:insert(?SEQ_WRITE_STORE, {K, V}),
    {reply, R, State};
handle_call({update, K, V}, _From, State) ->
    R = ets:update_element(?SEQ_WRITE_STORE, K, {2, V}),
    {reply, R, State};
handle_call({delete, K}, _From, State) ->
    R = ets:delete(?SEQ_WRITE_STORE, K),
    {reply, R, State};
handle_call(_Request, _From, State) ->
    %% {stop, Response, State}
    {reply, {error, not_implemented}, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({create, K, V}, State) ->
    ets:insert_new(?SEQ_WRITE_STORE, {K, V}),
    {noreply, State};
handle_cast({create_or_update, K, V}, State) ->
    ets:insert(?SEQ_WRITE_STORE, {K, V}),
    {noreply, State};
handle_cast({update, K, V}, State) ->
    ets:update_element(?SEQ_WRITE_STORE, K, {2, V}),
    {noreply, State};
handle_cast({delete, K}, State) ->
    ets:delete(?SEQ_WRITE_STORE, K),
    {noreply, State};
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


