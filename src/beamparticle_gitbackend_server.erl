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
-module(beamparticle_gitbackend_server).

-behaviour(gen_server).

-include("beamparticle_constants.hrl").

%% API
-export([start_link/1]).
-export([sync_write_file/4, async_write_file/3]).
-export([call/2, cast/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          port = undefined :: alcove_drv:ref()
}).

%%%===================================================================
%%% API
%%%===================================================================

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

-spec sync_write_file(Filename :: string(),
                      Content :: iolist(),
                      Msg :: string(),
                      TimeoutMsec :: integer()) ->
    {ok, Hash :: string(), ChangedFiles :: list(string())}
    | {error, disconnected}.
sync_write_file(Filename, Content, Msg, TimeoutMsec) ->
    call({write, Filename, Content, Msg}, TimeoutMsec).

-spec async_write_file(Filename :: string(),
                       Content :: iolist(),
                       Msg :: string()) -> ok.
async_write_file(Filename, Content, Msg) ->
    cast({write, Filename, Content, Msg}).

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
-spec cast(Message :: term())
        -> ok | {error, disconnected}.
cast(Message) ->
    try
        gen_server:cast(?SERVER, Message)
    catch
        exit:{noproc, _} ->
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
    {ok, #state{}, 0}.

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
handle_call({write, Filename, Content, Msg}, _From,
            #state{port = Drv} = State) ->
    Result = handle_file_write(Drv, Filename, Content, Msg),
    {reply, {ok, Result}, State};
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
handle_cast({write, Filename, Content, Msg}, #state{port = Drv} = State) when
      Drv =/= undefined ->
    handle_file_write(Drv, Filename, Content, Msg),
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
handle_info(timeout, State) ->
    GitBackendConfig = application:get_env(?APPLICATION_NAME, gitbackend, []),
    RootPath = proplists:get_value(rootpath, GitBackendConfig, "git-data"),
    Username = proplists:get_value(username, GitBackendConfig, "beamparticle"),
    Email = proplists:get_value(email, GitBackendConfig, "beamparticle@localhost"),
    FullRootPath = filename:absname(RootPath),

    %% Ensure that root folder exists else driver creation would fail
    %% Note that ensure_dir will only ensure that all parent directories exist
    Result = filelib:ensure_dir(filename:join([FullRootPath, "dummy"])),
    lager:info("git-backend [~p] FullRootPath = ~p, creation = ~p", [self(), FullRootPath, Result]),
    {ok, Drv} = beamparticle_container_util:create_driver(
                  simple, [{ctldir, FullRootPath}]),
    %% git-src shall be the main repository where complete source code
    %% and branches shall be maintained
    GitSourcePath = filename:join([FullRootPath, "git-src"]),
    %% the rest of these are deployment paths, where files shall be
    %% served as-is.
    UsersPath = filename:join([FullRootPath, "users"]),
    ProdPath = filename:join([FullRootPath, "prod"]),
    MasterPath = filename:join([FullRootPath, "master"]),
    lists:foreach(fun(X) ->
                          case filelib:is_dir(X) of
                              true -> ok;
                              false ->
                                  case filelib:is_file(X) of
                                      true -> file:delete(X);
                                      false -> ok
                                  end,
                                  lager:info("git-backend creating folder ~p",
                                             [X]),
                                  filelib:ensure_dir(filename:join([X, "dummy"])),
                                  case X of
                                      GitSourcePath ->
                                          TimeoutMsec = ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC,
                                          git_init(Drv, X, Username, Email,
                                                   TimeoutMsec),
                                          git_add_readme(Drv, X, TimeoutMsec),
                                          Branches = [<<"prod">>],
                                          git_add_branches(Drv, X, Branches,
                                                           TimeoutMsec);
                                      _ ->
                                          ok
                                  end
                          end
                  end, [GitSourcePath, UsersPath, ProdPath, MasterPath]),
    {noreply, State#state{port = Drv}};
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
terminate(Reason, State) ->
    lager:info("~p terminating, Reason, = ~p, State = ~p", [self(), Reason, State]),
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

handle_file_write(Drv, Filename, Content, Msg) ->
    GitBackendConfig = application:get_env(?APPLICATION_NAME, gitbackend, []),
    RootPath = proplists:get_value(rootpath, GitBackendConfig, "git-data"),
    FullRootPath = filename:absname(RootPath),
    GitSourcePath = filename:join([FullRootPath, "git-src"]),
    AbsoluteFilename = filename:join([GitSourcePath, Filename]),
    git_save_file(Drv, GitSourcePath, AbsoluteFilename,
                  Content, Msg, ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).


execute_command(Drv, Path, Command, Args, TimeoutMsec) ->
    {ok, ChildPID} = alcove:fork(Drv, []),
    alcove:chdir(Drv, [ChildPID], Path),
    EnvironmentVars = [],
    ok = alcove:execve(Drv, [ChildPID], Command, [Command | Args],
                       EnvironmentVars),
    lager:info("git-backend running command ~s ~s", [Command, Args]),
    receive
        {alcove_event, Drv, [ChildPID], {exit_status, ExitCode}} = Event ->
            lager:info("git-backend received event ~p", [Event]),
            Stdout = alcove:stdout(Drv, [ChildPID]),
            Stderr = alcove:stderr(Drv, [ChildPID]),
            {ExitCode, Stdout, Stderr}
    after
        TimeoutMsec ->
            {error, timeout}
    end.

git_init(Drv, Path, Username, Email, TimeoutMsec) ->
    {0, _, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, ["init"], TimeoutMsec),
    {0, _, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, ["config", "user.name", Username],
                  TimeoutMsec),
    {0, _, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, ["config", "user.email", Email],
                  TimeoutMsec).

git_add_readme(Drv, Path, TimeoutMsec) ->
    Readme = [<<"# README\n">>,
              <<"\n">>,
              <<"This folder contains the knowledge base for the node ">>,
              atom_to_binary(node(), utf8),
              <<"\n">>,
              <<"\n">>],
    Msg = "let the knowledge begin",
    AbsoluteFilename = filename:join([Path, "README.md"]),
    git_save_file(Drv, Path, AbsoluteFilename, Readme, Msg, TimeoutMsec).

git_add_branches(Drv, Path, Branches, TimeoutMsec) ->
    lists:foreach(fun(X) ->
                          {0, _, _} = execute_command(
                                        Drv, Path, ?GIT_BINARY,
                                        ["branch", X], TimeoutMsec)
                  end, Branches).

git_save_file(Drv, Path, FullFilename, Content, Msg, TimeoutMsec) ->
    lager:debug("git_save_file(~p)", [{Drv, Path, FullFilename, Content, Msg, TimeoutMsec}]),
    ok = file:write_file(FullFilename, Content),
    {0, _, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, ["add", FullFilename],
                  TimeoutMsec),
    CommitResult = execute_command(
                     Drv, Path, ?GIT_BINARY, ["commit", "-m", Msg],
                     TimeoutMsec),
    case CommitResult of
        {0, _, _} ->
            {0, HashStdout, _} = execute_command(
                          Drv, Path, ?GIT_BINARY, ["log", "-n1", "--format=\"%H\"",
                                                      "-n", "1"],
                          TimeoutMsec),
            %% when running git command via exec it returns the
            %% hash wrapped in double quotes, so remove them.
            Hash = re:replace(string:trim(HashStdout), <<"\"">>, <<>>, [{return, binary}, global]),
            {0, ChangedFilesWithCommitStdout, _} = execute_command(
                          Drv, Path, ?GIT_BINARY, ["show", "--oneline",
                                                      "--name-only", Hash],
                          TimeoutMsec),
            %% The first line is the abbreviated commit message,
            %% so ignore that
            [_ | ChangedFiles] = string:split(ChangedFilesWithCommitStdout, "\n", all),
            {ok, Hash, ChangedFiles};
        {1, _, _} ->
            %% nothing to commit, working directory clean
            {ok, "", []}
    end.
