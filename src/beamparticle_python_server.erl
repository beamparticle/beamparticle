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
-module(beamparticle_python_server).

-behaviour(gen_server).

-include("beamparticle_constants.hrl").

%% API
-export([create_pool/4]).
-export([start_link/1]).
-export([get_pid/0, call/2, cast/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
%% interval is in millisecond
-record(state, {
          id :: integer() | undefined,
          pynodename :: atom() | undefined,
          python_node_port
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Create a pool of dynamic function with given configuration
%%
%% A sample usage of this function is as follows:
%%
%% '''
%%     beamparticle_python_server:create_pool(1, 10000, 1, 500)
%% '''
%%
%% The name of the pool is always fixed to ?PYNODE_POOL_NAME
%% so this function can be called only once after startup.
-spec create_pool(PoolSize :: pos_integer(),
                  ShutdownDelayMsec :: pos_integer(),
                  MinAliveRatio :: float(),
                  ReconnectDelayMsec :: pos_integer())
        -> {ok, pid()} | {error, term()}.
create_pool(PoolSize, ShutdownDelayMsec,
            MinAliveRatio, ReconnectDelayMsec) ->
	PoolName = ?PYNODE_POOL_NAME,
	PoolWorkerId = pynode_pool_worker_id,
	Args = [],
    PoolChildSpec = {PoolWorkerId,
                     {?MODULE, start_link, [Args]},
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
    %% do not register a name, so as to attach in pool
    gen_server:start_link(?MODULE, Options, []).

%% @doc
%% Get the pid of least loaded worker for a given pool
-spec get_pid() -> pid() | {error, disconnected} | term().
get_pid() ->
	PoolName = ?PYNODE_POOL_NAME,
    palma:pid(PoolName).

%% @doc Send a sync message to a worker
-spec call(Message :: term(), TimeoutMsec :: non_neg_integer() | infinity)
        -> ok | {error, disconnected}.
call(Message, TimeoutMsec) ->
    case get_pid() of
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
-spec cast(Message :: term()) -> ok | {error, disconnected}.
cast(Message) ->
    case get_pid() of
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
init(_Args) ->
    %% pick random timeout, so as to avoid all workers starting
    %% at the same time and trying to find id, while coliding
    %% unnecessarily. Although, the resolution will still work
    %% via the seq_write store, but we can easily avoid this.
    TimeoutMsec = rand:uniform(100),
    {ok,
     #state{id = undefined,
            pynodename = undefined,
            python_node_port = undefined},
     TimeoutMsec}.

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
handle_info(timeout, State) ->
    {ok, Id} = find_worker_id(1),
    PythonExecutablePath = filename:join(
                           [code:priv_dir(?APPLICATION_NAME),
                            ?PYTHON_SERVER_EXEC_PATH]),
    lager:info("Python server node executable path ~p~n", [PythonExecutablePath]),
    ErlangNodeName = atom_to_list(node()),
    PythonNodeName = "python-" ++ integer_to_list(Id) ++ "-" ++ ErlangNodeName,
    %% erlang:list_to_atom/1 is dangerous but in this case bounded, so
    %% let this one go
    PythonNodeServerName = list_to_atom(PythonNodeName),
    Cookie = atom_to_list(erlang:get_cookie()),
    NumWorkers = integer_to_list(?MAXIMUM_PYNODE_WORKERS),
    PythonNodePort = erlang:open_port(
        {spawn_executable, PythonExecutablePath},
        [{args, [PythonNodeName, Cookie, ErlangNodeName, NumWorkers]},
         {line, 1000},
         use_stdio]
    ),
    lager:info("java server node started ~p~n", [PythonNodePort]),
    {noreply, State#state{
                id = Id,
                pynodename = PythonNodeServerName,
                python_node_port = PythonNodePort}};
handle_info(_Info, State) ->
    lager:info("Received ~p", _Info),
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
terminate(_Reason, State) ->
    erlang:port_close(State#state.python_node_port),
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

%% @private
%% @doc find available id for the python node
-spec find_worker_id(integer()) -> {ok, integer()} | {error, maximum_retries}.
find_worker_id(V) when V > ?MAXIMUM_PYNODE_SERVER_ID ->
    {error, maximum_retries};
find_worker_id(V) when V > 0 ->
    Name = "pynode-" ++ integer_to_list(V),
    case beamparticle_seq_write_store:create({pynodename, Name}, V) of
        true ->
            {ok, V};
        false ->
            find_worker_id(V + 1)
    end.
