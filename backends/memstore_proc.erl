%%% @doc Process keeping memstore stateful.
%%% Ignore if you are doing tutorial X.
-module(memstore_proc).
-behaviour(gen_server).
-export([start_link/1,
         create/4, read/3, update/4, delete/3,
         reset/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3, terminate/2]).

-ignore_xref([start_link/1, reset/1]).

-type name() :: atom().
-type key() :: term().
-type val() :: term().
-type state() :: term().

%%%%%%%%%%%%%%%%%%
%%% PUBLIC API %%%
%%%%%%%%%%%%%%%%%%
-spec start_link(atom()) -> {ok, pid()}.
start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

-spec create(name(), key(), val(), state()) -> boolean().
create(Name, K, V, _) ->
    gen_server:call(Name, {create, K, V}).

-spec read(name(), key(), state()) ->
        {ok, term()} | {error, not_found}.
read(Name, K, _) ->
    gen_server:call(Name, {read, K}).

-spec update(name(), key(), val(), state()) -> boolean().
update(Name, K, V, _) ->
    gen_server:call(Name, {update, K, V}).

-spec delete(name(), key(), state()) -> boolean().
delete(Name, K, _) ->
    gen_server:call(Name, {delete, K}).

%% @private clears the memstore data -- useful for tests.
reset(Name) ->
    gen_server:call(Name, reset).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% GEN_SERVER CALLBACKS %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([]) ->
    {ok, memstore:init()}.

handle_call({create, K, V}, _From, State) ->
    {reply, true, memstore:create(K, V, State)};
handle_call({read, K}, _From, State) ->
    {reply, memstore:read(K, State), State};
handle_call({update, K, V}, _From, State) ->
    {reply, true, memstore:update(K, V, State)};
handle_call({delete, K}, _From, State) ->
    {reply, true, memstore:delete(K, State)};
handle_call(reset, _From, _State) ->
    {reply, ok, memstore:init()}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_, _) ->
    ok.
