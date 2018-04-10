%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% Allocate terminals to clients and connect their shell-terminals
%%% with specific terminals.
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
-module(beamparticle_ide_terminals_server).
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
-export([create/1,
         read/1,
         delete/1]).

-define(SERVER, ?MODULE).

-define(DEFAULT_TIMEOUT_MSEC, 5000).

-record(state, {
          next_unsed_id = 0 :: integer(),
          term_info = #{} :: map(), %% key is id of terminal (integer) and the
                                    %% value is pid of shell-terminal
          shellterm_info = #{} :: map() %% key is pid of shell-terminal and value is
                                        %% list of all terminal ids (integer) largely
                                        %% for book-keeping and cleanup in case of
                                        %% failures.
         }).

%%%===================================================================
%%% API
%%%===================================================================

-spec create(pid()) -> {ok, integer()} | {error, term()}.
create(Pid) ->
    call({create, Pid}, ?DEFAULT_TIMEOUT_MSEC).

-spec read(pid() | integer()) -> {ok, pid()} | {error, term()}.
read(Id) when is_pid(Id) orelse is_integer(Id) ->
    call({read, Id}, ?DEFAULT_TIMEOUT_MSEC).

-spec delete(pid() | integer()) -> ok.
delete(Id) when is_pid(Id) orelse is_integer(Id) ->
    call({delete, Id}, ?DEFAULT_TIMEOUT_MSEC).

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
handle_call({create, Pid} = _Request, _From,
            #state{next_unsed_id = NextUnusedId,
                   term_info = TermInfo,
                   shellterm_info = ShellTermInfo} = State) ->
    TermInfo2 = TermInfo#{NextUnusedId => Pid},
    ShellTermMetaInfo = maps:get(Pid, ShellTermInfo, []),
    ShellTermInfo2 = ShellTermInfo#{Pid => [NextUnusedId | ShellTermMetaInfo]},
    %% monitor Pid, so when it dies we cleanup afterwords
    true = erlang:link(Pid),
    lager:info("[~p] created terminal Id = ~p, Pid = ~p", [self(), NextUnusedId, Pid]),
    State2 = State#state{next_unsed_id = NextUnusedId + 1,
                         term_info = TermInfo2,
                         shellterm_info = ShellTermInfo2},
    {reply, {ok, NextUnusedId}, State2};
handle_call({read, Id} = _Request, _From,
            #state{next_unsed_id = _NextUnusedId,
                   term_info = TermInfo,
                   shellterm_info = _ShellTermInfo} = State) when is_integer(Id) ->
    case maps:get(Id, TermInfo, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Pid ->
            {reply, {ok, Pid}, State}
    end;
handle_call({read, Pid} = _Request, _From,
            #state{next_unsed_id = _NextUnusedId,
                   term_info = _TermInfo,
                   shellterm_info = ShellTermInfo} = State) when is_pid(Pid) ->
    case maps:get(Pid, ShellTermInfo, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Ids ->
            {reply, {ok, Ids}, State}
    end;
handle_call({delete, Id} = _Request, _From,
            #state{next_unsed_id = _NextUnusedId,
                   term_info = TermInfo,
                   shellterm_info = ShellTermInfo} = State) when is_integer(Id) ->
    case maps:get(Id, TermInfo, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Pid ->
            TermInfo2 = maps:remove(Id, TermInfo),
            Ids = maps:get(Pid, ShellTermInfo, []),
            case Ids -- [Id] of
                [] ->
                    erlang:unlink(Pid),
                    ShellTermInfo2 = maps:remove(Pid, ShellTermInfo),
                    {reply, {ok, Pid}, State#state{term_info = TermInfo2,
                                                   shellterm_info = ShellTermInfo2}};
                RemainingIds ->
                    ShellTermInfo3 = ShellTermInfo#{Pid => RemainingIds},
                    {reply, {ok, Pid}, State#state{term_info = TermInfo2,
                                                   shellterm_info = ShellTermInfo3}}
            end
    end;
handle_call({delete, Pid} = _Request, _From,
            #state{next_unsed_id = _NextUnusedId,
                   term_info = TermInfo,
                   shellterm_info = ShellTermInfo} = State) when is_pid(Pid) ->

    case remove_terminals(Pid, TermInfo, ShellTermInfo) of
        {error, _} ->
            {reply, {error, not_found}, State};
        {TermInfo2, ShellTermInfo2} ->
            {reply, {ok, Pid}, State#state{term_info = TermInfo2,
                                           shellterm_info = ShellTermInfo2}}
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
handle_info({'EXIT', Pid, _} = Info, #state{term_info = TermInfo,
                                            shellterm_info = ShellTermInfo} = State) ->
    lager:info("[~p] ~p received Info = ~p, State = ~p", [self(), ?MODULE, Info, State]),
    case remove_terminals(Pid, TermInfo, ShellTermInfo) of
        {error, _} ->
            {noreply, State};
        {TermInfo2, ShellTermInfo2} ->
            {noreply, State#state{term_info = TermInfo2,
                                  shellterm_info = ShellTermInfo2}}
    end;
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
terminate(_Reason, #state{shellterm_info = ShellTermInfo} = _State) ->
    %% unlink everything
    lists:foreach(fun(E) ->
                          erlang:unlink(E)
                  end, maps:keys(ShellTermInfo)),
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

remove_terminals(Pid, TermInfo, ShellTermInfo) ->
    case maps:get(Pid, ShellTermInfo, undefined) of
        undefined ->
            {error, not_found};
        Ids ->
            %% technically the free terminal id can be reused
            TermInfo2 = lists:foldl(fun(E, AccIn) ->
                                            maps:remove(E, AccIn)
                                    end, TermInfo, Ids),
            erlang:unlink(Pid),
            ShellTermInfo2 = maps:remove(Pid, ShellTermInfo),
            {TermInfo2, ShellTermInfo2}
    end.

