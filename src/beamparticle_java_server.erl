%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% TODO: This is very similar to beamparticle_python_server,
%%%       so plan to make it generic and reuse code as much
%%%       possible.
%%%
%%% TODO: terminate may not be invoked always,
%%% specifically in case of erlang:exit(Pid, kill)
%%% So, the node name is never released. FIXME
%%% Id will LEAK if the above is not fixed.
%%%
%%% UPDATE: queue is now mantained but maximum queue depth is not
%%%         configurable.
%%% TODO: maintain queue and allow cancellation of jobs from a given
%%%       caller process id. Additionally, monitor health of caller
%%%       processes, who made gen_server:call (not cast although
%%%       cast also are ultimately sent to connected java node
%%%       as gen_server:call). If the caller process dies then
%%%       cancel the job (if it is currently running if possible
%%%       preferably by sending a cancel message via the stdin interface,
%%%       which must be read by java node in another thread),
%%%       or do not run the earlier posted job even when that was
%%%       queued.
%%%
%%% TODO: set environment variable while starting java node
%%%       and ensure that libraries are picked up from a given
%%%       lib folder. This will allow dynamically adding more
%%%       libraries (or updating them), which will then be
%%%       made effective by restarting the java node (at present
%%%       although libraries can be dynamically loaded in the
%%%       future via the stdin interface).
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
-module(beamparticle_java_server).

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

-define(SERVER, ?MODULE).
%% interval is in millisecond
-record(state, {
          id = undefined :: integer() | undefined,
          javanodename = undefined :: atom() | undefined,
          java_node_port = undefined :: port() | undefined,
          q :: queue:queue(),  %% maintain a queue with a maximum depth and start rejecting further calls
          qlen = 0 :: non_neg_integer(),
              %% maintain monitor links in the queued request as well (that is pid)
          tref = undefined,  %% a timer reference for current job
          worker = undefined :: pid() | undefined  %% pid of actor which makes gen_server:call/3 to java node
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Create a pool of dynamic function with given configuration
%%
%% A sample usage of this function is as follows:
%%
%% '''
%%     beamparticle_java_server:create_pool(1, 10000, 1, 500)
%% '''
%%
%% The name of the pool is always fixed to ?JAVANODE_POOL_NAME
%% so this function can be called only once after startup.
%%
%% Note that this function shall return {error, not_found}
%% when the java node is not available along with this
%% software. This is primarily provided to keep java
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
            PoolName = ?JAVANODE_POOL_NAME,
            PoolWorkerId = javanode_pool_worker_id,
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
            palma:new(PoolName, PoolSize, PoolChildSpec,
                      ShutdownDelayMsec, RevolverOptions)
    end.

%% @doc Destroy the pool for java nodes.
-spec destroy_pool() -> ok.
destroy_pool() ->
	PoolName = ?JAVANODE_POOL_NAME,
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
	PoolName = ?JAVANODE_POOL_NAME,
    palma:pid(PoolName).

%% @doc Send a sync message to a worker
%%
%% Note that TimeoutMsec must be greater than 5000.
-spec call(Message :: term(), TimeoutMsec :: non_neg_integer() | infinity)
        -> ok | {error, disconnected | wrong_timeout}.
call(Message, TimeoutMsec) when TimeoutMsec > 5000 ->
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
    end;
call(_Message, _) ->
    {error, wrong_timeout}.

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
     #state{q = queue:new()},
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
handle_call({get_javanode_id, _}, _From, #state{id = Id} = State) ->
    {reply, {ok, Id}, State};
handle_call({{load, Fname, Code}, TimeoutMsec},
            From,
            #state{javanodename = JavaServerNodeName} = State)
  when JavaServerNodeName =/= undefined ->
    Message = {'com.beamparticle.JavaLambdaStringEngine',
               'load',
               [Fname, Code]},
    case schedule_request(Message, From, TimeoutMsec, JavaServerNodeName, State) of
        overload ->
            {reply, {error, overload}, State};
        State2 ->
            {noreply, State2}
    end;
handle_call({{eval, Code}, TimeoutMsec},
            From,
            #state{javanodename = JavaServerNodeName} = State)
  when JavaServerNodeName =/= undefined ->
    Message = {'com.beamparticle.JavaLambdaStringEngine',
               'evaluate',
               [Code]},
    case schedule_request(Message, From, TimeoutMsec, JavaServerNodeName, State) of
        overload ->
            {reply, {error, overload}, State};
        State2 ->
            {noreply, State2}
    end;
handle_call({{invoke, Fname, Arguments}, TimeoutMsec},
            From,
            #state{javanodename = JavaServerNodeName} = State)
  when JavaServerNodeName =/= undefined ->
    %% Note that arguments when passed to java node must be tuple.
    Message = {'com.beamparticle.JavaLambdaStringEngine',
               'invoke',
               [Fname, Arguments]},
    case schedule_request(Message, From, TimeoutMsec, JavaServerNodeName, State) of
        overload ->
            {reply, {error, overload}, State};
        State2 ->
            {noreply, State2}
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
    {JavaNodePort, JavaServerNodeName} = start_java_node(Id),
    {noreply, State#state{
                id = Id,
                javanodename = JavaServerNodeName,
                java_node_port = JavaNodePort}};
handle_info({P, {exit_status, Code}}, #state{id = Id, java_node_port = P} = State) ->
    lager:info("Java node Id = ~p, Port = ~p terminated with Code = ~p, restarting",
               [Id, P, Code]),
    {JavaNodePort, _} = start_java_node(Id),
    {noreply, State#state{java_node_port = JavaNodePort}};
handle_info({timeout, Ref, tick}, #state{id = Id, tref = Ref} = State) ->
    %% java node is taking too long to respond, probably it is time
    %% to terminate the call.
    erlang:exit(State#state.worker, kill),
    %% TODO: find a better mechanism, but for now terminate the port
    kill_external_process(State#state.java_node_port),
    erlang:port_close(State#state.java_node_port),
    lager:info("Terminating stuck Java node Id = ~p, Port = ~p, restarting",
               [Id, State#state.java_node_port]),
    {JavaNodePort, _} = start_java_node(Id),
    State2 = State#state{java_node_port = JavaNodePort},
    %% TODO: avoid restarting java node and device threading and killing that
    %% thread to bail out whenever possible.
    %% terminating java node is costly, since we need to reload all the
    %% dynamic java functions again.

    case queue:out(State2#state.q) of
        {{value, {CallerPid, _, _}}, Q2} ->
            Qlen = State2#state.qlen - 1,
            gen_server:reply(CallerPid, {error, timeout}),
            case queue:peek(Q2) of
                {value, {_, Message, TimeoutMsec}} ->
                    JavaServerNodeName = State2#state.javanodename,
                    Ref = erlang:start_timer(TimeoutMsec, self(), tick),
                    WorkerPid = async_execute(JavaServerNodeName, Message),
                    State3 = State2#state{q = Q2, qlen = Qlen,
                                          tref = Ref, worker = WorkerPid},
                    {noreply, State3};
                _ ->
                    {noreply, State2#state{q = Q2, qlen = Qlen,
                                           tref = undefined, worker = undefined}}
            end;
        {empty, Q2} ->
            %% ideally this should never have happened
            {noreply, State2#state{q = Q2, qlen = 0, tref = undefined, worker = undefined}}
    end;
handle_info({'EXIT', Pid, {normal, R}}, #state{worker = Pid} = State) ->
    erlang:cancel_timer(State#state.tref, [{async, true}]),
    Qlen = State#state.qlen - 1,
    case queue:out(State#state.q) of
        {{value, {CallerPid, _, _}}, Q2} ->
            gen_server:reply(CallerPid, R),
            case queue:peek(Q2) of
                {value, {_, Message, TimeoutMsec}} ->
                    Ref = erlang:start_timer(TimeoutMsec, self(), tick),
                    JavaServerNodeName = State#state.javanodename,
                    WorkerPid = async_execute(JavaServerNodeName, Message),
                    State2 = State#state{q = Q2, qlen = Qlen,
                                         tref = Ref, worker = WorkerPid},
                    {noreply, State2};
                _ ->
                    {noreply, State#state{q = Q2, qlen = Qlen,
                                          tref = undefined, worker = undefined}}
            end;
        {empty, Q2} ->
            %% ideally this should never have happened
            {noreply, State#state{q = Q2, qlen = 0,
                                  tref = undefined, worker = undefined}}
    end;
handle_info(_Info, State) ->
    lager:info("~p received info ~p", [?SERVER, _Info]),
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
terminate(_Reason, #state{id = Id, java_node_port = undefined} = _State) ->
    case Id of
        undefined ->
            ok;
        _ ->
            Name = "javanode-" ++ integer_to_list(Id),
            %% TODO: terminate may not be invoked always,
            %% specifically in case of erlang:exit(Pid, kill)
            %% So, the node name is never released. FIXME
            %% Id will LEAK if the above is not fixed.
            lager:info("java node, Id = ~p, Pid = ~p terminated", [Id, self()]),
            beamparticle_seq_write_store:delete_async({javanodename, Name})
    end,
    ok;
terminate(_Reason, #state{id = Id} = State) ->
    %% under normal circumstances hard kill is not required
    %% but it is difficult to guess, so lets just do that
    kill_external_process(State#state.java_node_port),
    erlang:port_close(State#state.java_node_port),
    Name = "javanode-" ++ integer_to_list(Id),
    %% TODO: terminate may not be invoked always,
    %% specifically in case of erlang:exit(Pid, kill)
    %% So, the node name is never released. FIXME
    %% Id will LEAK if the above is not fixed.
    lager:info("java node, Id = ~p, Pid = ~p terminated", [Id, self()]),
    beamparticle_seq_write_store:delete_async({javanodename, Name}),
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
%% @doc find available id for the java node
-spec find_worker_id(integer()) -> {ok, integer()} | {error, maximum_retries}.
find_worker_id(V) when V > ?MAXIMUM_JAVANODE_SERVER_ID ->
    {error, maximum_retries};
find_worker_id(V) when V > 0 ->
    Name = "javanode-" ++ integer_to_list(V),
    case beamparticle_seq_write_store:create({javanodename, Name}, self()) of
        true ->
            {ok, V};
        false ->
            find_worker_id(V + 1)
    end.

%% @private
%% @doc Fullpath of the executable file for starting java node.
-spec get_executable_file_path() -> list().
get_executable_file_path() ->
    filename:join(
      [code:priv_dir(?APPLICATION_NAME),
       ?JAVA_SERVER_EXEC_PATH]).

%% @private
%% @doc Start java node with given Id.
-spec start_java_node(Id :: integer()) -> {JavaNode :: port(),
                                           JavaServerNodeName :: atom()}.
start_java_node(Id) ->
    JavaExecutablePath = get_executable_file_path(),
    lager:info("Java server Id = ~p node executable path ~p~n", [Id, JavaExecutablePath]),
    ErlangNodeName = atom_to_list(node()),
    JavaNodeName = "java-" ++ integer_to_list(Id) ++ "-" ++ ErlangNodeName,
    %% erlang:list_to_atom/1 is dangerous but in this case bounded, so
    %% let this one go
    JavaServerNodeName = list_to_atom(JavaNodeName),
    Cookie = atom_to_list(erlang:get_cookie()),
    LogPath = filename:absname("log/javanode-" ++ integer_to_list(Id) ++ ".log"),
    LogLevel = "INFO",
    JavaExtraLibFolder = filename:absname("javalibs"),
    JavaNodeConfig = application:get_env(?APPLICATION_NAME, javanode, []),
    JavaOpts = proplists:get_value(javaopts, JavaNodeConfig, ""),
    EnvironmentVariables = [{"JAVA_OPTS",
                             JavaOpts
                             ++ " -classpath \""
                             ++ JavaExtraLibFolder ++ "/*.jar"
                             ++ "\""}],
    JavaNodePort = erlang:open_port(
        {spawn_executable, JavaExecutablePath},
        [{args, [JavaNodeName, Cookie, ErlangNodeName,
                LogPath, LogLevel]},
         {packet, 4}  %% send 4 octet size (network-byte-order) before payload
         ,{env, EnvironmentVariables}
         ,use_stdio
         ,binary
         ,exit_status
        ]
    ),
    lager:info("java server node started Id = ~p, Port = ~p~n", [Id, JavaNodePort]),
    timer:sleep(?JAVANODE_DEFAULT_STARTUP_TIME_MSEC),
    %% now load some functions, assuming that the service is up
    load_all_java_functions(JavaServerNodeName),
    {JavaNodePort, JavaServerNodeName}.

load_all_java_functions(JavaServerNodeName) ->
    FunctionPrefix = <<>>,  %% No hard requirement for naming python functions
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         erlang:throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         try
                             case beamparticle_erlparser:detect_language(V) of
                                 {java, Code, _} ->
                                     Fname = ExtractedKey,
                                     Message = {'com.beamparticle.JavaLambdaStringEngine',
                                                'load',
                                                [Fname, Code]},
                                     gen_server:call({?JAVANODE_MAILBOX_NAME,
                                                      JavaServerNodeName},
                                                      Message);
                                 _ ->
                                     ok
                             end,
                             AccIn
                         catch
                             _:_ ->
                                 AccIn  %% ignore error for now (TODO)
                         end;
                     _ ->
                         erlang:throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, function),
    Resp.

%% @private
%% @doc Kill external process via kill signal (hard kill).
%% This strategy is required when the external process might be
%% blocked or stuck (due to bad software or a lot of work).
%% The only way to preemt is to hard kill the process.
-spec kill_external_process(Port :: port()) -> ok.
kill_external_process(Port) ->
    {os_pid, OsPid} = erlang:port_info(Port, os_pid),
    os:cmd(io_lib:format("kill -9 ~p", [OsPid])).

-spec async_execute(JavaServerNodeName :: atom(), Message :: term()) -> pid().
async_execute(JavaServerNodeName, Message) ->
    %% TODO: rather than being stuck in gen_server:call, lets maintain requests
    %% in our own queue instead to gain more control and allow cancelling of
    %% jobs as well (with given process id).
    erlang:spawn_link(fun() ->
        try
            R = gen_server:call({?JAVANODE_MAILBOX_NAME, JavaServerNodeName},
                                Message,
                                infinity),  %% lets not worry about timeout here
            exit({normal, R})
        catch
            C:E ->
                exit({error, {error, {exception, {C, E}}}})
        end
                      end).

-spec schedule_request(Message :: tuple(),
                       From :: term(),
                       TimeoutMsec :: integer(),
                       JavaServerNodeName :: atom(),
                       State :: term()) -> State :: term() | overload.
schedule_request(_Message, _From, _TimeoutMsec, _JavaServerNodeName,
                 #state{qlen = Qlen} = _State) when Qlen > ?JAVANODE_MAX_QUEUE_DEPTH ->
    overload;
schedule_request(Message, From, TimeoutMsec, JavaServerNodeName, State) ->
    Q = State#state.q,
    %% top of the queue is message under processing, so we
    %% need to queue the message always
    Q2 = queue:in({From, Message, TimeoutMsec}, Q),
    Qlen = State#state.qlen + 1,
    case {queue:is_empty(Q), State#state.worker} of
        {true, undefined} ->
            Ref = erlang:start_timer(TimeoutMsec, self(), tick),
            WorkerPid = async_execute(JavaServerNodeName, Message),
            %% Response :: {ok, Arity :: integer()} | {error, not_found | term()}
            State2 = State#state{q = Q2, qlen = Qlen, tref = Ref, worker = WorkerPid},
            State2;
        {false, P} when is_pid(P) ->
            %% TODO check for overload
            State#state{q = Q2, qlen = Qlen}
    end.

