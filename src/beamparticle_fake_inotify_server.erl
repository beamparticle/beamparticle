%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% Fake inotify server, which gets update from multiple places
%%% and distribute changes to observers.
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
-module(beamparticle_fake_inotify_server).
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
-export([watch/2,
         unwatch/1,
         add_handler/3]).

-export([event_close_write/1]).

-type path() :: string().

-define(SERVER, ?MODULE).

-define(DEFAULT_TIMEOUT_MSEC, 5000).

-record(state, {
          ref_info = #{} :: map() %% key is WatchRef and value is path
         }).

%%%===================================================================
%%% API
%%%===================================================================

-spec watch(path(), Opts :: [close_write]) -> reference() | {error, term()}.
watch(Path, [close_write]) ->
    call({watch, Path, [close_write]}, ?DEFAULT_TIMEOUT_MSEC).

-spec unwatch(reference()) -> ok | {error, term()}.
unwatch(Ref) ->
    call({unwatch, Ref}, ?DEFAULT_TIMEOUT_MSEC).

-spec add_handler(reference(), atom(), term()) -> ok | {error, term()}.
add_handler(Ref, Module, Arg) ->
    call({add_handler, Ref, Module, Arg}, ?DEFAULT_TIMEOUT_MSEC).

-spec event_close_write(path()) -> ok.
event_close_write(Path) when is_list(Path) ->
    cast({event, Path, [close_write]}).

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
    erlang:process_flag(trap_exit, true),
    {ok, #state{}}.

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
handle_call({watch, Path, [close_write]} = _Request, _From,
            #state{ref_info = RefInfo} = State) ->
    Ref = erlang:make_ref(),
    RefInfo2 = RefInfo#{Ref => {Path, undefined}},
    {reply, Ref, State#state{ref_info = RefInfo2}};
handle_call({unwatch, Ref} = _Request, _From,
            #state{ref_info = RefInfo} = State) ->
    RefInfo2 = maps:remove(Ref, RefInfo),
    {reply, ok, State#state{ref_info = RefInfo2}};
handle_call({add_handler, Ref, Module, Arg} = _Request, _From,
            #state{ref_info = RefInfo} = State) ->
    case maps:get(Ref, RefInfo, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        {Path, _} ->
            RefInfo2 = RefInfo#{Ref => {Path, {Module, Arg}}},
            {reply, ok, State#state{ref_info = RefInfo2}}
    end;
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
handle_cast({event, Path, [close_write]} = _Request,
            #state{ref_info = RefInfo} = State) ->
    M = maps:filter(fun(_K, {P, {_Module, _Arg}}) when P == Path -> true;
                       (_K, {P, {_Module, _Arg}}) ->
                            string:prefix(P, Path) =/= nomatch
                    end, RefInfo),
    Msg = {inotify_msg, [close_write], 0, list_to_binary(Path)},
    maps:fold(fun(K, {_, {Module, Arg}}, AccIn) ->
                      %% try Module:inotify_event(Arg, K, Msg) catch _:_ -> ok end,
                      Module:inotify_event(Arg, K, Msg),
                      AccIn
              end, [], M),
    {noreply, State};
handle_cast(Request, State) ->
    lager:info("[~p] Received Request = ~p, State = ~p", [self(), Request, State]),
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
handle_info({'EXIT', _Pid, _} = Info, State) ->
    %% TODO remove ref
    State2 = State,
    lager:info("[~p] ~p received Info = ~p, State = ~p", [self(), ?MODULE, Info, State2]),
    {noreply, State2};
handle_info(Info, State) ->
    lager:info("[~p] ~p received Info = ~p", [self(), ?MODULE, Info]),
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


