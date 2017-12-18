%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
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
-module(beamparticle_generic_pool_worker).

-behaviour(gen_server).

%% API
-export([create_pool/7]).
-export([start_link/1]).

-export([get_pid/1, call/3, cast/2]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    function :: binary(),
    function_initial_argument :: term(),
    %% data can be used by generic function to store anything
    data :: term()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Create a pool of dynamic function with given configuration
-spec create_pool(PoolName :: atom(),
                  PoolSize :: pos_integer(),
                  PoolWorkerId :: atom(),
                  ShutdownDelayMsec :: pos_integer(),
                  MinAliveRatio :: float(),
                  ReconnectDelayMsec :: pos_integer(),
                  {Fun :: function(), InitialArg :: term()})
        -> {ok, pid()} | {error, term()}.
create_pool(PoolName, PoolSize, PoolWorkerId, ShutdownDelayMsec,
            MinAliveRatio, ReconnectDelayMsec,
            {Fun, InitialArg}) when is_function(Fun, 2) ->
    PoolChildSpec = {PoolWorkerId,
                     {?MODULE, start_link, [ [Fun, InitialArg] ]},
                     {permanent, 5},
                      ShutdownDelayMsec,
                      worker,
                      [?MODULE]
                    },
    RevolverOptions = #{
      min_alive_ratio => MinAliveRatio,
      reconnect_delay => ReconnectDelayMsec},
    lager:info("Starting PalmaPool = ~p", [PoolName]),
    palma:new(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec, RevolverOptions).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Options :: list()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Options) ->
    %% create unnamed process, so that it can be supervised as
    %% pool of workers
    gen_server:start_link(?MODULE, Options, []).

%% @doc
%% Get the pid of least loaded worker for a given pool
-spec get_pid(atom()) -> pid() | {error, disconnected} | term().
get_pid(PoolName) ->
    palma:pid(PoolName).

%% @doc Send a sync message to a worker
-spec call(PoolName :: atom(), Message :: term(), TimeoutMsec :: non_neg_integer() | infinity)
        -> ok | {error, disconnected}.
call(PoolName, Message, TimeoutMsec) when is_atom(PoolName)->
    case get_pid(PoolName) of
        Pid when is_pid(Pid) ->
            try
                gen_server:call(Pid, Message, TimeoutMsec)
            catch
                exit:{noproc, _} ->
                    {error, disconnected}
            end;
        _ ->
            {error, disconnected}
    end.

%% @doc Send an async message to a worker
-spec cast(PoolName :: atom(), Message :: term()) -> ok | {error, disconnected}.
cast(PoolName, Message) when is_atom(PoolName)->
    case get_pid(PoolName) of
        Pid when is_pid(Pid) ->
            try
                gen_server:cast(Pid, Message)
            catch
                exit:{noproc, _} ->
                    {error, disconnected}
            end;
        _ ->
            {error, disconnected}
    end.

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
init([Function, InitialArgument]) ->
    Result = Function(InitialArgument, {init}),
    case Result of
        {ok, Data} ->
            {ok, #state{function = Function,
                        function_initial_argument = InitialArgument,
                        data = Data}};
        {ok, Data, hibernate} ->
            {ok, #state{function = Function,
                        function_initial_argument = InitialArgument,
                        data = Data}, hibernate};
        {ok, Data, Timeout} when is_integer(Timeout) ->
            {ok, #state{function = Function,
                        function_initial_argument = InitialArgument,
                        data = Data}, Timeout};
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.

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
handle_call(Request, From,
            #state{function = Function,
                   function_initial_argument = InitialArgument,
                   data = Data} = State) ->
    Result = Function(InitialArgument, {call, Request, From, Data}),
    %% TODO log result for failure or success
    case Result of
        {reply, Reply, NewData} ->
            {reply, Reply, State#state{data = NewData}};
        {reply, Reply, NewData, T} when is_integer(T)
                                        orelse T == hibernate ->
            {reply, Reply, State#state{data = NewData}, T};
        {noreply, NewData} ->
            {noreply, State#state{data = NewData}};
        {noreply, NewData, T} when is_integer(T)
                                   orelse T == hibernate ->
            {noreply, State#state{data = NewData}, T};
        {stop, Reason, Reply, NewData} ->
            {stop, Reason, Reply, State#state{data = NewData}};
        {stop, Reason, NewData} ->
            {stop, Reason, State#state{data = NewData}}
    end.

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
handle_cast(Request,
            #state{function = Function,
                   function_initial_argument = InitialArgument,
                   data = Data} = State) ->
    Result = Function(InitialArgument, {cast, Request, Data}),
    case Result of
        {noreply, NewData} ->
            {noreply, State#state{data = NewData}};
        {noreply, NewData, T} when is_integer(T)
                                   orelse T == hibernate ->
            {noreply, State#state{data = NewData}, T};
        {stop, Reason, NewData} ->
            {stop, Reason, State#state{data = NewData}}
    end.

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
handle_info(Info,
            #state{function = Function,
                   function_initial_argument = InitialArgument,
                   data = Data} = State) ->
    Result = Function(InitialArgument, {info, Info, Data}),
    case Result of
        {noreply, NewData} ->
            {noreply, State#state{data = NewData}};
        {noreply, NewData, T} when is_integer(T)
                                   orelse T == hibernate ->
            {noreply, State#state{data = NewData}, T};
        {stop, Reason, NewData} ->
            {stop, Reason, State#state{data = NewData}}
    end.

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
terminate(Reason,
          #state{function = Function,
                 function_initial_argument = InitialArgument,
                 data = Data} = _State) ->
    %% return value do not matter
    Function(InitialArgument, {terminate, Reason, Data}),
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
code_change(OldVsn,
            #state{function = Function,
                   function_initial_argument = InitialArgument,
                   data = Data} = State,
           Extra) ->
    Result = Function(InitialArgument, {code_change, OldVsn, Data, Extra}),
    case Result of
        {ok, NewData} ->
            {ok, State#state{data = NewData}};
        {error, Reason} ->
            {error, Reason}
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

