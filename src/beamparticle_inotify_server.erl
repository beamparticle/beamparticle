%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% Watch over changes in filesystem like a hawk.
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
-module(beamparticle_inotify_server).
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
         unwatch/2,
         unwatch/1]).

%% API for inotify_evt to call back
-export([inotify_event/3]).

-type path() :: string().

-define(SERVER, ?MODULE).

-define(DEFAULT_TIMEOUT_MSEC, 5000).

-record(state, {
          watcher_info = #{} :: map(), %% key is pid of watcher and value is
                                 %% list of paths
          path_info = #{} :: map(), %% key is path and value is
                             %% {ListOfWatcherPid, WatchRef}
          ref_info = #{} :: map() %% key is WatchRef and value is path
         }).

%%%===================================================================
%%% API
%%%===================================================================

-spec watch(path(), pid()) -> ok | {error, term()}.
watch(Path, Pid) ->
    call({watch, Path, Pid}, ?DEFAULT_TIMEOUT_MSEC).

-spec unwatch(path(), pid()) -> ok | {error, term()}.
unwatch(Path, Pid) ->
    cast({unwatch, Path, Pid}).

-spec unwatch(pid()) -> ok | {error, term()}.
unwatch(Pid) ->
    cast({unwatch, Pid}).

-spec inotify_event(Arg :: term(), EventTag :: term(), Msg :: term()) ->
    ok | remove_handler.
inotify_event(Arg, EventTag, Msg) ->
    lager:info("inotify_event(~p, ~p, ~p)", [Arg, EventTag, Msg]),
    %% sample event is as follows:
    %% <0.4152.0>, #Ref<0.2328466614.3838312450.214364>, {inotify_msg,[close_write],0,"hello"}
    %%
    %% IMPORTANT: sometime [ignored] is also received when higher-level event is generated
    cast({event, Arg, EventTag, Msg}),
    %% when this method returns the remove_handler atom
    %% then this shall be removed automatically from inotify
    ok.

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
handle_call({watch, Path, Pid} = _Request, _From,
            #state{watcher_info = WatcherInfo,
                   path_info = PathInfo,
                   ref_info = RefInfo} = State) ->
    case maps:get(Path, PathInfo, undefined) of
        undefined ->
            PathStr = binary_to_list(Path),
            %% TODO: the pattern for saving files is only when its closed
            %% so the clients which modify the files must close them as well.
            try
                case beamparticle_fake_inotify_server:watch(PathStr, [close_write]) of
                    {error, _} = ErrorMsg ->
                        {reply, ErrorMsg, State};
                    Ref1 ->
                        ok = beamparticle_fake_inotify_server:add_handler(Ref1, ?MODULE, self()),
                        PathInfo2 = PathInfo#{Path => {[Pid], Ref1}},
                        WatcherMetaInfo = maps:get(Pid, WatcherInfo, []),
                        WatcherInfo2 = WatcherInfo#{Pid => [Path | WatcherMetaInfo]},
                        RefInfo2 = RefInfo#{Ref1 => Path},
                        %% monitor Pid, so when it dies we cleanup afterwords
                        true = erlang:link(Pid),
                        lager:info("[~p] Started watching Path = ~p, Pid = ~p, Ref = ~p", [self(), Path, Pid, Ref1]),
                        State2 = State#state{watcher_info = WatcherInfo2,
                                    path_info = PathInfo2,
                                    ref_info = RefInfo2},
                        {reply, ok, State2}
                end
            catch
                _:_ ->
                    lager:error("[~p] Cannot watch Path = ~p, Pid = ~p", [self(), Path, Pid]),
                    {reply, {error, not_found}, State}
            end;
        PathMetaInfo ->
            {ListOfWatcherPid, WatchRef} = PathMetaInfo,
            case lists:member(Pid, ListOfWatcherPid) of
                true ->
                    %% already a member
                    lager:info("[~p] Already watching Path = ~p, Pid = ~p, Ref = ~p", [self(), Path, Pid, WatchRef]),
                    {reply, ok, State};
                false ->
                    %% register
                    PathMetaInfo2 = {[Pid | ListOfWatcherPid], WatchRef},
                    PathInfo3 = PathInfo#{Path => PathMetaInfo2},
                    WatcherMetaInfo2 = maps:get(Pid, WatcherInfo, []),
                    WatcherInfo3 = WatcherInfo#{Pid => [Path | WatcherMetaInfo2]},
                    true = erlang:link(Pid),
                    lager:info("[~p] Registered Path = ~p, Pid = ~p, Ref = ~p", [self(), Path, Pid, WatchRef]),
                    State3 = State#state{watcher_info = WatcherInfo3,
                                         path_info = PathInfo3},
                    {reply, ok, State3}
            end
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
handle_cast({event, _Arg, EventTag,
             {inotify_msg, [EventFlag], 0, FilePath}} = _Request,
            #state{watcher_info = _WatcherInfo,
                   path_info = PathInfo,
                   ref_info = RefInfo} = State) when
      EventFlag == close_write orelse EventFlag == ignored ->
    case maps:get(EventTag, RefInfo, undefined) of
        undefined ->
            lager:info("[~p] Cannot find Path for EventTag = ~p, State = ~p", [self(), EventTag, State]),
            ok;
        Path ->
            lager:info("[~p] Discovered Path = ~p, FilePath = ~p, State = ~p", [self(), Path, FilePath, State]),
            {ListOfWatcherPid, _} = maps:get(Path, PathInfo),
            lists:foreach(fun(E) ->
                                  E ! {inotify_event, {close_write, Path}}
                          end, ListOfWatcherPid),
            %% join and try to send nother notification for the indicated file
            AdditionalPath = iolist_to_binary([Path, <<"/">>, FilePath]),
            case maps:get(AdditionalPath, PathInfo, undefined) of
                undefined ->
                    ok;
                {AdditionalListOfWatcherPid, _} ->
                    lists:foreach(fun(E) ->
                                          E ! {inotify_event, {close_write, AdditionalPath}}
                                  end, AdditionalListOfWatcherPid),
                    ok
            end
    end,
    {noreply, State};
handle_cast({unwatch, Path, Pid} = Request, State) ->
    State2 = remove_watcher(Path, Pid, State),
    lager:info("[~p] ~p received request = ~p, State = ~p", [self(), ?MODULE, Request, State2]),
    {noreply, State2};
handle_cast({unwatch, Pid} = Request, State) ->
    State2 = remove_watcher(Pid, State),
    lager:info("[~p] ~p received request = ~p, State = ~p", [self(), ?MODULE, Request, State2]),
    {noreply, State2};
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
handle_info({'EXIT', Pid, _} = Info, State) ->
    State2 = remove_watcher(Pid, State),
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
terminate(_Reason, #state{ref_info = RefInfo} = _State) ->
    %% unwatch everything with inotify
    lists:foreach(fun(E) ->
                          beamparticle_fake_inotify_server:unwatch(E)
                  end, maps:keys(RefInfo)),
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

%% can call this within lists:foldl/3 or lists:foldr/3.
remove_watcher_path(E, {Pid, {NewPathInfo, NewRefInfo}}) ->
    case maps:get(E, NewPathInfo) of
        {ListOfWatcherPid, WatchRef} ->
            %% TODO this is costly for many watchers
            case ListOfWatcherPid -- [Pid] of
                [] ->
                    %% stop watching the path completely
                    PathInfo2 = maps:remove(E, NewPathInfo),
                    RefInfo2 = maps:remove(WatchRef, NewRefInfo),
                    beamparticle_fake_inotify_server:unwatch(WatchRef),
                    {Pid, {PathInfo2, RefInfo2}};
                UpdatedListOfWatcherPid ->
                    NewPathInfo2 = NewPathInfo#{E => {
                                       UpdatedListOfWatcherPid,
                                       WatchRef}},
                    {Pid, {NewPathInfo2, NewRefInfo}}
            end;
        _ ->
            {Pid, {NewPathInfo, NewRefInfo}}
    end.

remove_watcher(Pid,
               #state{watcher_info = WatcherInfo,
                      path_info = PathInfo,
                      ref_info = RefInfo} = State) ->
    R = case maps:get(Pid, WatcherInfo, undefined) of
            undefined ->
                {Pid, {PathInfo, RefInfo}}; 
            ListOfWatcherPaths ->
                lists:foldl(fun remove_watcher_path/2,
                            {Pid, {PathInfo, RefInfo}}, ListOfWatcherPaths)
        end,
    {_, {PathInfo3, RefInfo3}} = R,
    WatcherInfo2 = maps:remove(Pid, WatcherInfo),
    State#state{watcher_info = WatcherInfo2,
                path_info = PathInfo3,
                ref_info = RefInfo3}.

remove_watcher(Path,
               Pid,
               #state{watcher_info = WatcherInfo,
                      path_info = PathInfo,
                      ref_info = RefInfo} = State) ->
    R = case maps:get(Pid, WatcherInfo, undefined) of
            undefined ->
                {WatcherInfo, PathInfo, RefInfo};
            [Path] ->
                WatcherInfo2 = maps:remove(Pid, WatcherInfo),
                {_, {PathInfo2, RefInfo2}} = remove_watcher_path(
                                               Path, {Pid, {PathInfo, RefInfo}}),
                {WatcherInfo2, PathInfo2, RefInfo2};
            ListOfWatcherPaths ->
                {_, {PathInfo3, RefInfo3}} = remove_watcher_path(
                                               Path, {Pid, {PathInfo, RefInfo}}),
                WatcherInfo3 = WatcherInfo#{Pid => ListOfWatcherPaths -- [Path]},
                {WatcherInfo3, PathInfo3, RefInfo3}
        end,
    {WatcherInfo4, PathInfo4, RefInfo4} = R,
    State#state{watcher_info = WatcherInfo4,
                path_info = PathInfo4,
                ref_info = RefInfo4}.

