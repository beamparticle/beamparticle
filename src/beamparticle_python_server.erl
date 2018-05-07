%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% TODO: terminate may not be invoked always,
%%% specifically in case of erlang:exit(Pid, kill)
%%% So, the node name is never released. FIXME
%%% Id will LEAK if the above is not fixed.
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
-export([create_pool/4, destroy_pool/0]).
-export([start_link/1]).
-export([get_pid/0, call/2, cast/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-export([wait_for_remote/2]).

-define(SERVER, ?MODULE).
%% interval is in millisecond
-record(state, {
          id :: integer() | undefined,
          pynodename :: atom() | undefined,
          python_node_port,
          new_interpreter_every_request = false :: boolean()
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
%%
%% Note that this function shall return {error, not_found}
%% when the python node is not available along with this
%% software. This is primarily provided to keep python
%% dependencies optional while running beamparticle.
-spec create_pool(PoolSize :: pos_integer(),
                  ShutdownDelayMsec :: pos_integer(),
                  MinAliveRatio :: float(),
                  ReconnectDelayMsec :: pos_integer())
        -> {ok, pid()} | {error, not_found | term()}.
create_pool(PoolSize, ShutdownDelayMsec,
            MinAliveRatio, ReconnectDelayMsec) ->
    ExecFilename = get_executable_file_path(),
    case os:find_executable(ExecFilename) of
        false ->
            {error, not_found};
        _ ->
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
            lager:info("[~p] ~p Starting PalmaPool = ~p", [self(), ?MODULE, PoolName]),
            palma:new(PoolName, PoolSize, PoolChildSpec,
                      ShutdownDelayMsec, RevolverOptions)
    end.

%% @doc Destroy the pool for python nodes.
-spec destroy_pool() -> ok.
destroy_pool() ->
	PoolName = ?PYNODE_POOL_NAME,
    palma:stop(PoolName).

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
                MessageWithTimeout = {Message, TimeoutMsec},
                gen_server:call(Pid, MessageWithTimeout, TimeoutMsec)
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
    erlang:process_flag(trap_exit, true),
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
handle_call({get_pynode_id, _}, _From, #state{id = Id} = State) ->
    {reply, {ok, Id}, State};
handle_call({{load, Fname, Code, Config}, TimeoutMsec},
            _From,
            #state{id = Id, pynodename = PythonServerNodeName,
                   python_node_port = OldPythonNodePort} = State)
  when PythonServerNodeName =/= undefined ->
    Message = {<<"MyProcess">>,
               <<"load">>,
               {Fname, Code, Config}},
    try
        %% R :: {ok, Arity :: integer()} | {error, not_found | term()}
        read_earlier_logs(PythonServerNodeName, OldPythonNodePort),
        R = gen_server:call({?PYNODE_MAILBOX_NAME, PythonServerNodeName},
                            Message,
                           TimeoutMsec),
        {Drv2, ChildPID} = OldPythonNodePort,
        Stdout = read_alcove_process_log(Drv2, ChildPID, stdout),
        Stderr = read_alcove_process_log(Drv2, ChildPID, stderr),
        {reply, {R, {log, Stdout, Stderr}}, State}
    catch
        C:E ->
            %% under normal circumstances hard kill is not required
            %% but it is difficult to guess, so lets just do that
            kill_external_process(State#state.python_node_port),
            lager:info("[~p] ~p Terminating stuck Python node Id = ~p, Port = ~p, restarting",
                       [self(), ?MODULE, Id, State#state.python_node_port]),
            {PythonNodePort, _} = case OldPythonNodePort of
                                      {Drv, _} ->
                                          start_python_node(Drv, Id);
                                      undefined ->
                                          start_python_node(undefined, Id)
                                  end,
            State2 = State#state{python_node_port = PythonNodePort},
            {reply, {error, {exception, {C, E}}}, State2}
    end;
handle_call({{eval, Code}, TimeoutMsec},
            _From,
            #state{id = Id, pynodename = PythonServerNodeName,
                   python_node_port = OldPythonNodePort} = State)
  when PythonServerNodeName =/= undefined ->
    Message = {<<"MyProcess">>,
               <<"eval">>,
               {Code}},
    try
        read_earlier_logs(PythonServerNodeName, OldPythonNodePort),
        R = gen_server:call({?PYNODE_MAILBOX_NAME, PythonServerNodeName},
                            Message,
                            TimeoutMsec),
        {Drv2, ChildPID} = OldPythonNodePort,
        Stdout = read_alcove_process_log(Drv2, ChildPID, stdout),
        Stderr = read_alcove_process_log(Drv2, ChildPID, stderr),
        {reply, {R, {log, Stdout, Stderr}}, State}
    catch
        C:E ->
            %% under normal circumstances hard kill is not required
            %% but it is difficult to guess, so lets just do that
            kill_external_process(State#state.python_node_port),
            lager:info("[~p] ~p Terminating stuck Python node Id = ~p, Port = ~p, restarting",
                       [self(), ?MODULE, Id, State#state.python_node_port]),
            {PythonNodePort, _} = case OldPythonNodePort of
                                      {Drv, _} ->
                                          start_python_node(Drv, Id);
                                      undefined ->
                                          start_python_node(undefined, Id)
                                  end,
            State2 = State#state{python_node_port = PythonNodePort},
            {reply, {error, {exception, {C, E}}}, State2}
    end;
handle_call({{invoke, Fname, PythonExpressionBin, Config, Arguments}, TimeoutMsec},
            _From,
            #state{id = Id, pynodename = PythonServerNodeName,
                   python_node_port = OldPythonNodePort,
                   new_interpreter_every_request = StartNewInterpreterEveryRequest} = State)
  when PythonServerNodeName =/= undefined ->
    %% Note that arguments when passed to python node must be tuple.
    Message = {<<"MyProcess">>,
               <<"invoke">>,
               {Fname, PythonExpressionBin, Config, list_to_tuple(Arguments)}},
    try
        read_earlier_logs(PythonServerNodeName, OldPythonNodePort),
        R = gen_server:call({?PYNODE_MAILBOX_NAME, PythonServerNodeName},
                            Message, TimeoutMsec),
        {Drv2, ChildPID} = OldPythonNodePort,
        Stdout = read_alcove_process_log(Drv2, ChildPID, stdout),
        Stderr = read_alcove_process_log(Drv2, ChildPID, stderr),
        case StartNewInterpreterEveryRequest of
            false -> ok;
            true -> gen_server:cast(self(), restart_pynode)
        end,
        {reply, {R, {log, Stdout, Stderr}}, State}
    catch
        C:E ->
            State3 = restart_pynode(Id, OldPythonNodePort, State),
            {reply, {error, {exception, {C, E}}}, State3}
    end;
handle_call({{invoke_simple_http, Fname, PythonExpressionBin, Config, DataBin, ContextBin}, TimeoutMsec},
            _From,
            #state{id = Id, pynodename = PythonServerNodeName,
                   python_node_port = OldPythonNodePort,
                   new_interpreter_every_request = StartNewInterpreterEveryRequest} = State)
  when PythonServerNodeName =/= undefined ->
    %% Note that arguments when passed to python node must be tuple.
    Message = {<<"MyProcess">>,
               <<"invoke_simple_http">>,
               {Fname, PythonExpressionBin, Config, DataBin, ContextBin}},
    try
        read_earlier_logs(PythonServerNodeName, OldPythonNodePort),
        R = gen_server:call({?PYNODE_MAILBOX_NAME, PythonServerNodeName},
                            Message, TimeoutMsec),
        %% TODO limit the volume of logs to limited size, while discarding
        %% anything above some limit
        {Drv2, ChildPID} = OldPythonNodePort,
        Stdout = read_alcove_process_log(Drv2, ChildPID, stdout),
        Stderr = read_alcove_process_log(Drv2, ChildPID, stderr),
        case StartNewInterpreterEveryRequest of
            false -> ok;
            true -> gen_server:cast(self(), restart_pynode)
        end,
        {reply, {R, {log, Stdout, Stderr}}, State}
    catch
        C:E ->
            State3 = restart_pynode(Id, OldPythonNodePort, State),
            {reply, {error, {exception, {C, E}}}, State3}
    end;
handle_call(load_all_python_functions, _From,
            #state{pynodename = PythonServerNodeName} = State) ->
    R = load_all_python_functions(PythonServerNodeName),
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
handle_cast(restart_pynode,
            #state{
               id = Id,
               python_node_port = OldPythonNodePort} = State) ->
    State2 = restart_pynode(Id, OldPythonNodePort, State),
    {noreply, State2};
handle_cast(load_all_python_functions, #state{pynodename = PythonServerNodeName} = State) ->
    load_all_python_functions(PythonServerNodeName),
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
handle_info(timeout, #state{python_node_port = OldPythonNodePort} = State) ->
    {ok, Id} = find_worker_id(1),
    {PythonNodePort, PythonServerNodeName} = case OldPythonNodePort of
                                                 {Drv, _} ->
                                                     start_python_node(Drv, Id);
                                                 undefined ->
                                                     start_python_node(undefined, Id)
                                             end,
    PynodeConfig = application:get_env(?APPLICATION_NAME, pynode, []),

    StartNewInterpreterEveryRequest = case proplists:get_value(restart_policy,
                                                               PynodeConfig,
                                                               none) of
                                          none -> false;
                                          every_request -> true
                                      end,
    {noreply, State#state{
                id = Id,
                pynodename = PythonServerNodeName,
                python_node_port = PythonNodePort,
                new_interpreter_every_request = StartNewInterpreterEveryRequest}};
handle_info({'EXIT', Drv, _Reason} = Info,
            #state{id = Id,
                   python_node_port = {Drv, ChildPID}} = State) ->
    %% The driver died, which is strange but restart it anyways
    lager:info("[~p] ~p Python node Id = ~p, Port = ~p terminated with Info = ~p, restarting",
               [self(), ?MODULE, Id, {Drv, ChildPID}, Info]),
    {PythonNodePort, _} = start_python_node(undefined, Id),
    {noreply, State#state{python_node_port = PythonNodePort}};
%%{alcove_event, Drv, [ChildPID], {signal, sigchld}}
%%{alcove_stdout, Drv, [PID], Data}
%%{alcove_stderr, Drv, [PID], Data}
handle_info({alcove_event, Drv, [ChildPID], {stopsig, _Type}} = Info,
            #state{id = Id,
                   python_node_port = {Drv, ChildPID}} = State) ->
    %% when the python node is killed with "kill -9"
    lager:info("[~p] ~p Python node Id = ~p, Port = ~p terminated with Info = ~p, restarting",
               [self(), ?MODULE, Id, {Drv, ChildPID}, Info]),
    {PythonNodePort, _} = start_python_node(Drv, Id),
    {noreply, State#state{python_node_port = PythonNodePort}};
handle_info({alcove_event, Drv, [ChildPID], {exit_status, _Status}} = Info,
            #state{id = Id,
                   python_node_port = {Drv, ChildPID}} = State) ->
    %% when the python node is killed with "kill -9"
    lager:info("[~p] ~p Python node Id = ~p, Port = ~p terminated with Info = ~p, restarting",
               [self(), ?MODULE, Id, {Drv, ChildPID}, Info]),
    {PythonNodePort, _} = start_python_node(Drv, Id),
    {noreply, State#state{python_node_port = PythonNodePort}};
handle_info({alcove_event, Drv, [ChildPID], {termsig, _Signal}} = Info,
            #state{id = Id,
                   python_node_port = {Drv, ChildPID}} = State) ->
    %% when the python node is killed with "kill -9"
    lager:info("[~p] ~p Python node Id = ~p, Port = ~p terminated with Info = ~p, restarting",
               [self(), ?MODULE, Id, {Drv, ChildPID}, Info]),
    {PythonNodePort, _} = start_python_node(Drv, Id),
    {noreply, State#state{python_node_port = PythonNodePort}};
handle_info(_Info, State) ->
    lager:info("[~p] ~p received info ~p", [self(), ?SERVER, _Info]),
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
terminate(_Reason, #state{id = Id, python_node_port = undefined} = _State) ->
    case Id of
        undefined ->
            ok;
        _ ->
            Name = "pynode-" ++ integer_to_list(Id),
            %% TODO: terminate may not be invoked always,
            %% specifically in case of erlang:exit(Pid, kill)
            %% So, the node name is never released. FIXME
            %% Id will LEAK if the above is not fixed.
            lager:info("python node, Id = ~p, Pid = ~p terminated", [Id, self()]),
            beamparticle_seq_write_store:delete_async({pynodename, Name})
    end,
    ok;
terminate(_Reason, #state{id = Id} = State) ->
    %% under normal circumstances hard kill is not required
    %% but it is difficult to guess, so lets just do that
    kill_external_process(State#state.python_node_port),
    Name = "pynode-" ++ integer_to_list(Id),
    %% TODO: terminate may not be invoked always,
    %% specifically in case of erlang:exit(Pid, kill)
    %% So, the node name is never released. FIXME
    %% Id will LEAK if the above is not fixed.
    lager:info("python node, Id = ~p, Pid = ~p terminated", [Id, self()]),
    beamparticle_seq_write_store:delete_async({pynodename, Name}),
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
    case beamparticle_seq_write_store:create({pynodename, Name}, self()) of
        true ->
            {ok, V};
        false ->
            find_worker_id(V + 1)
    end.

%% @private
%% @doc Fullpath of the executable file for starting python node.
-spec get_executable_file_path() -> list().
get_executable_file_path() ->
    filename:join(
      [code:priv_dir(?APPLICATION_NAME),
       ?PYTHON_SERVER_EXEC_PATH]).

%% @private
%% @doc Start python node with given Id.
-spec start_python_node(Drv :: undefined | alcove_drv:ref(), Id :: integer()) ->
    {PythonNode :: {pid(), integer()},
     PythonServerNodeName :: atom()}.
start_python_node(OldDrv, Id) ->
    PythonExecutablePath = get_executable_file_path(),
    lager:info("[~p] ~p Python server Id = ~p node executable path ~p~n",
               [self(), ?MODULE, Id, PythonExecutablePath]),
    ErlangNodeName = atom_to_list(node()),
    PythonNodeName = "python-" ++ integer_to_list(Id) ++ "@127.0.0.1",
    %% erlang:list_to_atom/1 is dangerous but in this case bounded, so
    %% let this one go
    PythonServerNodeName = list_to_atom(PythonNodeName),
    Cookie = atom_to_list(erlang:get_cookie()),
    NumWorkers = integer_to_list(?MAXIMUM_PYNODE_WORKERS),
    LogPath = filename:absname("log/pynode-" ++ integer_to_list(Id) ++ ".log"),
    LogLevel = "INFO",
    PythonExtraLibFolder = filename:absname("pythonlibs"),
    PythonExtraLibs = lists:flatten(
                        lists:join(":",
                                   filelib:wildcard(
                                     PythonExtraLibFolder ++ "/*.zip"))),
    {ok, Drv} = case OldDrv of
                    undefined ->
                        %% IMPORTANT: the ctldir must exist, else driver
                        %% init will fail.
                        beamparticle_container_util:create_driver(simple, [{ctldir, filename:absname(".")}]);
                        %%beamparticle_container_util:create_driver(simple, [{ctldir, filename:absname("pynode-ctldir")}]);
                    _ ->
                        {ok, OldDrv}
                end,
    EnvironmentVars = ["PYTHON_OPT_PATH=" ++ PythonExtraLibs],
    {ok, ChildPID} = beamparticle_container_util:create_child(
                       simple, Drv, <<>>, PythonExecutablePath,
                       [PythonNodeName, Cookie, ErlangNodeName, NumWorkers, LogPath, LogLevel], 
                       EnvironmentVars, []),
    PythonNodePort = {Drv, ChildPID},
    lager:info("[~p] ~p python server node started Id = ~p, Port = ~p~n",
               [self(), ?MODULE, Id, PythonNodePort]),
    %%ok = wait_for_remote(PythonServerNodeName, 10),
    %% now load some functions, assuming that the service is up
    %% the all-upfront loading is not scalable because it will
    %% consume a lot of resources while scanning through the function
    %% data store and loading all the python functions to all the
    %% pythong execution nodes (like these when they are in huge
    %% numbers).
    %% Intead always send the source code to python node for them
    %% to check for updates and take appropriate action.
    %% load_all_python_functions(PythonServerNodeName),
    {PythonNodePort, PythonServerNodeName}.

-spec load_all_python_functions(PythonServerNodeName :: atom()) ->
    {ok, NumPythonFunctions :: non_neg_integer()} |
    {error, {exceptiom, {Classs :: term(), Reason :: term()}}}.
load_all_python_functions(PythonServerNodeName) ->
    FunctionPrefix = <<>>,  %% No hard requirement for naming python functions
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         erlang:throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         try
                             lager:debug("processing function key = ~p", [K]),
                             case beamparticle_erlparser:detect_language(V) of
                                 {python, Code, StoredConfig, _} ->
                                     %% TODO pass configuration to pynode
                                     Fname = ExtractedKey,
                                     [FnameWithoutArity, _] = binary:split(Fname, <<"/">>),
                                     Config = case StoredConfig of
                                                  <<>> -> <<"{}">>;
                                                  _ -> StoredConfig
                                              end,
                                     Message = {<<"MyProcess">>,
                                                <<"load">>,
                                                {FnameWithoutArity, Code, Config}},
                                     lager:debug("loading python function ~p, message = ~p",
                                                 [Fname,
                                                  {?PYNODE_MAILBOX_NAME,
                                                   PythonServerNodeName,
                                                   Message}]),
                                     gen_server:call({?PYNODE_MAILBOX_NAME,
                                                      PythonServerNodeName},
                                                     Message),
                                     {[Fname | R], S2};
                                 _ ->
                                     AccIn
                             end
                         catch
                             _:_ ->
                                 AccIn  %% ignore error for now (TODO)
                         end;
                     _ ->
                         erlang:throw({{ok, R}, S2})
                 end
         end,
    try
        %% There is a possibility that the storage is busy
        %% and do not allow full function scan, so lets not
        %% crash because of that
        {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, function),
        {ok, length(Resp)}
    catch
        C:E ->
            {error, {exception, {C, E}}}
    end.

%% @private
%% @doc Kill external process via kill signal (hard kill).
%% This strategy is required when the external process might be
%% blocked or stuck (due to bad software or a lot of work).
%% The only way to preemt is to hard kill the process.
-spec kill_external_process(Port :: {alcove_drv:ref(), alcove:pid_t()}) -> ok.
kill_external_process(Port) ->
    {Drv, ChildPID} = Port,
    %% sigkill = -9
    alcove:kill(Drv, [], ChildPID, 9).

wait_for_remote(_PythonServerNodeName, 0) ->
    {error, maximum_attempts};
wait_for_remote(PythonServerNodeName, N) when N > 0 ->
    case net_adm:ping(PythonServerNodeName) of
        pong ->
            ok;
        pang ->
            timer:sleep(?PYNODE_DEFAULT_STARTUP_TIME_MSEC),
            wait_for_remote(PythonServerNodeName, N - 1)
    end.


read_alcove_process_log(Drv, ChildPID, stdout) ->
    case alcove:stdout(Drv, [ChildPID]) of
        Log when is_binary(Log) ->
            Log;
        Log when is_list(Log) ->
            iolist_to_binary(Log);
        _ ->
            <<>>
    end;
read_alcove_process_log(Drv, ChildPID, stderr) ->
    case alcove:stderr(Drv, [ChildPID]) of
        Log when is_binary(Log) ->
            Log;
        Log when is_list(Log) ->
            iolist_to_binary(Log);
        _ ->
            <<>>
    end.

restart_pynode(Id, OldPythonNodePort, State) ->
    %% under normal circumstances hard kill is not required
    %% but it is difficult to guess, so lets just do that
    kill_external_process(State#state.python_node_port),
    lager:info("[~p] ~p Terminating Python node Id = ~p, Port = ~p, restarting",
               [self(), ?MODULE, Id, State#state.python_node_port]),
    {PythonNodePort, _} = case OldPythonNodePort of
                              {Drv, _} ->
                                  start_python_node(Drv, Id);
                              undefined ->
                                  start_python_node(undefined, Id)
                          end,
    State#state{python_node_port = PythonNodePort}.

read_earlier_logs(PythonServerNodeName, OldPythonNodePort) ->
    %% read any leftover stdout or stderr before invoking the function
    {Drv2, ChildPID} = OldPythonNodePort,
    OldStdout = read_alcove_process_log(Drv2, ChildPID, stdout),
    OldStderr = read_alcove_process_log(Drv2, ChildPID, stderr),
    case byte_size(OldStdout) > 0 of
        true ->
            lager:info("[stdout] ~p: ~s", [PythonServerNodeName, OldStdout]);
        _ ->
            ok
    end,
    case byte_size(OldStderr) > 0 of
        true ->
            lager:info("[stderr] ~p: ~s", [PythonServerNodeName, OldStderr]);
        _ ->
            ok
    end.

