%%%-------------------------------------------------------------------
%%% @doc
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

-module(leveldbstore).
-export([init/1, create/3, read/2, update/3, delete/2, dropall/1, terminate/1]).
-export([timer_expired/1, delete_expired_keys/1]).
-export([lapply/3, drop_db_and_create_again/1]).

-include("beamparticle_constants.hrl").

-record(state, {
    dbpath,
    dboptions,
    ref,
    timer_ref
}).

-type state() :: #state{}.

-spec init(Args :: term()) -> state().
init([DbPath, DbOptions, TimeoutMsec]) ->
    {ok, Ref} = open(DbPath, DbOptions),
    {ok, TRef} = timer:apply_interval(TimeoutMsec, ?MODULE, timer_expired, [self()]),
    lager:info("Ref=~p, TRef=~p", [Ref, TRef]),
    #state{dbpath = DbPath, dboptions = DbOptions, ref = Ref, timer_ref = TRef}.

-spec create(K :: binary(), V :: binary(), State :: state()) -> {ok | {error, any()}, state()}.
create(K, V, State) ->
    Resp = case eleveldb:put(State#state.ref, K, V, []) of
               ok ->
                   cache_if_required(K, V),
                   ok;
               {error, Reason} ->
                   {error, Reason}
           end,
    lager:debug("create(~p,~p,~p) -> ~p", [K, V, State, Resp]),
    {Resp, State}.

-spec read(K :: binary(), State :: state()) -> {{ok, V ::binary()} | {error, not_found}, state()}.
read(K, State) ->
    %% read from in-memory cache first
    %% TODO: the model would have read from cache already,
    %% so do not do that here and assume that the info is not
    %% present.
    Resp = case beamparticle_cache_util:get(K) of
               {ok, Data} ->
                   {ok, Data};
               _ ->
                   case eleveldb:get(State#state.ref, K, []) of
                       {ok, V} ->
                           cache_if_required(K, V),  %% fix cache
                           {ok, V};
                       not_found -> {error, not_found};
                       {error, Reason} -> {error, Reason}
                   end
           end,
    lager:debug("read(~p~p) -> ~p", [K, State, Resp]),
    {Resp, State}.

-spec update(K :: binary(), V :: binary(), State :: state()) -> {ok | {error, any()}, state()}.
update(K, V, State) ->
    cache_if_required(K, V),
    Resp = eleveldb:put(State#state.ref, K, V, []),
    lager:debug("update(~p,~p,~p) -> ~p", [K, V, State, Resp]),
    {Resp, State}.

-spec delete(K :: binary(), State :: state()) -> {ok | {error, not_found}, state()}.
delete(K, State) ->
    Resp = eleveldb:delete(State#state.ref, K, []),
    lager:debug("delete(~p,~p) -> ~p", [K, State, Resp]),
    case K of
        <<?KSTORE_EXPIRY_TYPE, _Id/binary>> -> ok;
        _ ->
            beamparticle_cache_util:async_remove(K),
            %% delete the associated expiry key (if present)
            eleveldb:delete(State#state.ref, <<?KSTORE_EXPIRY_TYPE, K/binary>>, []),
            ok
    end,
    {Resp, State}.

-spec dropall(State :: state()) -> ok.
dropall(State) ->
    %%drop_db_and_create_again(State).
    delete_all_keys(State).

-spec terminate(State :: state()) -> ok.
terminate(State) ->
    % TODO check for any errors?
    timer:cancel(State#state.timer_ref),
    eleveldb:close(State#state.ref),
    ok.

-spec timer_expired(Pid :: pid()) -> ok.
timer_expired(Pid) when is_pid(Pid) ->
    gen_server:cast(Pid, mark_and_sweep).

-spec lapply(fun(({binary(), binary()}, {term(), state()}) -> {term(), state()}),
                binary(), state()) -> {ok, term()} | {error, term()}.
lapply(Fn, KeyPrefix, State) ->
    AccIn = {[], State},
    Opts = [
        {first_key, KeyPrefix},
        {fill_cache, false}
    ],
    try
        {Resp, State2} = eleveldb:fold(State#state.ref, Fn, AccIn, Opts),
        {{ok, Resp}, State2}
    catch
        throw: {{ok, Reason}, State3} ->
            {{ok, Reason}, State3}
    end.

-spec delete_expired_keys(state()) -> ok.
delete_expired_keys(State) ->
    {Mega, Sec, _Micro} = os:timestamp(),
    NowInSeconds = Mega * 1000 + Sec,
    AccIn = {?MAX_KEY_DELETES_PER_MARK_AND_SWEEP, NowInSeconds, State},
    Opts = [
        {first_key, <<?KSTORE_EXPIRY_TYPE>>},
        {fill_cache, false}
    ],
    try
        eleveldb:fold(
            State#state.ref, fun maybe_delete_expired_key/2, AccIn, Opts)
    catch
        throw: _Reason -> ok
    end,
    ok.

maybe_delete_expired_key({<<?KSTORE_EXPIRY_TYPE, Id/binary>> = K, <<Seconds:64>>},
                         {NumKeysPerSweepRemaining, NowInSeconds, State} = AccIn) when NumKeysPerSweepRemaining > 0 ->
    lager:debug("maybe_delete_expired_key({~p, ~p}, ~p)", [K, Seconds, AccIn]),
    case (NowInSeconds - Seconds) of
        Delta when Delta >= 0 ->
            lager:debug("posting expire key=~w at time=~w, with delta=~w sec ", [Id, NowInSeconds, Delta]),
            %{ok, State2} = delete(Id, State),
            gen_server:cast(self(), {delete, Id}),
            %{ok, State3} = delete(K, State2),
            %%[Id | AccIn];
            {NumKeysPerSweepRemaining - 1, NowInSeconds, State};
        _ ->
            %%TODO: should we just pre-empty and throw() here as well
            %%so that no iteration (due to sorted nature of keys)?
            {NumKeysPerSweepRemaining - 1, NowInSeconds, State}
    end;
maybe_delete_expired_key({_K, _V}, AccIn) ->
    %% done expiring keys and terminate the loop
    %% inside the eleveldb:fold/4 now.
    throw({ok, AccIn}).

-spec delete_all_keys(state()) -> state().
delete_all_keys(State) ->
    eleveldb:fold_keys(
        State#state.ref,
        fun (K, _AccIn) -> delete(K, State) end,
        [],
        [{fill_cache, false}]),
    State.

-spec drop_db_and_create_again(state()) -> state().
drop_db_and_create_again(State) ->
    DbPath = State#state.dbpath,
    DbOptions = State#state.dboptions,
    eleveldb:close(State#state.ref),
    eleveldb:destroy(DbPath, []),
    {ok, Ref} = eleveldb:open(DbPath, [{create_if_missing, true}] ++ DbOptions),
    State#state{dbpath = DbPath, dboptions = DbOptions, ref = Ref}.

-spec is_normal_key(Key :: binary()) -> boolean().
is_normal_key(Key) ->
    case Key of
        <<?KSTORE_EXPIRY_TYPE, _Id/binary>> -> false;
        _ -> true
    end.

-spec cache_if_required(K :: binary(), V :: binary()) -> ok.
cache_if_required(K, V) ->
    case is_normal_key(K) of
        true ->
            beamparticle_cache_util:async_put(K, V);
        _ -> ok
    end.

%% Private
open(DbPath, DbOptions) ->
    try
        eleveldb:open(DbPath, [{create_if_missing, true}] ++ DbOptions)
    catch
        error:{db_open, _} ->
            eleveldb:repair(DbPath, DbOptions)
    end.