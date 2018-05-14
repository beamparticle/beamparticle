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
-export([sync_write_file/3,
         async_write_file/2,
         sync_commit_file/4,
         async_commit_file/3]).
-export([git_status/2
         ,git_add/3
         ,git_log/4
         ,git_log_details/3
         ,git_log_details/5
         ,git_list_branches/2
         ,git_current_branch/2
         ,git_show/3
         ,git_revert/3
         ,get_git_source_path/0
         ]).
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

%% Modify the file but do not commit
-spec sync_write_file(Filename :: string(),
                      Content :: iolist(),
                      TimeoutMsec :: integer()) ->
    ok | {error, disconnected}.
sync_write_file(Filename, Content, TimeoutMsec) ->
    lager:debug("[~p] ~p sync_write_file(~p, ~p, ~p)", [self(), ?MODULE, Filename, Content, TimeoutMsec]),
    call({write, Filename, Content}, TimeoutMsec).

%% Modify the file but do not commit
-spec async_write_file(Filename :: string(),
                       Content :: iolist()) -> ok.
async_write_file(Filename, Content) ->
    cast({write, Filename, Content}).

%% Write file and commit it as well.
-spec sync_commit_file(Filename :: string(),
                       Content :: iolist(),
                       Msg :: string(),
                       TimeoutMsec :: integer()) ->
    {ok, Hash :: string(), ChangedFiles :: list(string())}
    | {error, disconnected}.
sync_commit_file(Filename, Content, Msg, TimeoutMsec) ->
    call({commit, Filename, Content, Msg}, TimeoutMsec).

%% Write file and commit it as well.
-spec async_commit_file(Filename :: string(),
                        Content :: iolist(),
                        Msg :: string()) -> ok.
async_commit_file(Filename, Content, Msg) ->
    cast({commit, Filename, Content, Msg}).


-spec git_status(Path :: string(),
                 TimeoutMsec :: integer()) ->
    {ok, Changes :: [map()]}
    | {error, disconnected | not_found}.
git_status(Path, TimeoutMsec) ->
    call({git_status, Path}, TimeoutMsec).

-spec git_add(Path :: string(),
              RelativeFilePath :: binary(),
              TimeoutMsec :: integer()) ->
    ok
    | {error, disconnected | not_found}.
git_add(Path, RelativeFilePath, TimeoutMsec) ->
    call({git_add, Path, RelativeFilePath}, TimeoutMsec).

-spec git_log(Path :: string(),
              HashType :: short | long,
              RelativeFilePath :: binary(),
              TimeoutMsec :: integer()) ->
    {ok, Hashes :: [binary()]}
    | {error, disconnected | not_found}.
git_log(Path, HashType, RelativeFilePath, TimeoutMsec) ->
    call({git_log, Path, HashType, RelativeFilePath}, TimeoutMsec).

-spec git_log_details(Path :: string(),
                      StartSha1 :: binary(),
                      EndSha1 :: binary(),
                      RelativeFilePath :: binary(),
                      TimeoutMsec :: integer()) ->
    {ok, Info :: [map()]}
    | {error, disconnected | not_found}.
git_log_details(Path, StartSha1, EndSha1, RelativeFilePath, TimeoutMsec) ->
    call({git_log_details, Path, StartSha1, EndSha1, RelativeFilePath}, TimeoutMsec).

-spec git_log_details(Path :: string(),
                      RelativeFilePath :: binary(),
                      TimeoutMsec :: integer()) ->
    {ok, Info :: [map()]}
    | {error, disconnected | not_found}.
git_log_details(Path, RelativeFilePath, TimeoutMsec) ->
    call({git_log_details, Path, RelativeFilePath}, TimeoutMsec).

-spec git_list_branches(Path :: string(),
                        TimeoutMsec :: integer()) ->
    {ok, Branches :: [map()]}
    | {error, disconnected | not_found}.
git_list_branches(Path, TimeoutMsec) ->
    call({git_list_branches, Path}, TimeoutMsec).

-spec git_current_branch(Path :: string(),
                         TimeoutMsec :: integer()) ->
    {ok, Branch :: binary()}
    | {error, disconnected | not_found}.
git_current_branch(Path, TimeoutMsec) ->
    call({git_current_branch, Path}, TimeoutMsec).

%% Note that GitObjectName must follow the conventions of
%% gitrevisions. See "SPECIFYING REVISIONS" for details.
-spec git_show(Path :: string(),
               GitObjectName :: binary(),
               TimeoutMsec :: integer()) ->
    {ok, Content :: binary()}
    | {error, disconnected | not_found}.
git_show(Path, GitObjectName, TimeoutMsec) ->
    call({git_show, Path, GitObjectName}, TimeoutMsec).

-spec git_revert(Path :: string(),
                 RelativeFilePath :: binary(),
                 TimeoutMsec :: integer()) ->
    ok | {error, disconnected | not_found}.
git_revert(Path, RelativeFilePath, TimeoutMsec) ->
    call({git_revert, Path, RelativeFilePath}, TimeoutMsec).

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
handle_call({write, Filename, Content}, _From,
            State) ->
    Result = handle_file_write(Filename, Content),
    {reply, Result, State};
handle_call({commit, Filename, Content, Msg}, _From,
            #state{port = Drv} = State) ->
    Result = handle_file_write_and_commit(Drv, Filename, Content, Msg),
    {reply, Result, State};
handle_call({git_status, Path}, _From,
            #state{port = Drv} = State) ->
    Result = handle_status(Drv, Path),
    {reply, Result, State};
handle_call({git_add, Path, RelativeFilePath}, _From,
            #state{port = Drv} = State) ->
    Result = handle_add(Drv, Path, RelativeFilePath),
    {reply, Result, State};
handle_call({git_log, Path, HashType, RelativeFilePath}, _From,
            #state{port = Drv} = State) ->
    Result = handle_log(Drv, Path, HashType, RelativeFilePath),
    {reply, Result, State};
handle_call({git_log_details, Path, RelativeFilePath}, _From,
            #state{port = Drv} = State) ->
    Result = handle_log_details(Drv, Path, RelativeFilePath),
    {reply, Result, State};
handle_call({git_log_details, Path, StartSha1, EndSha1, RelativeFilePath}, _From,
            #state{port = Drv} = State) ->
    Result = handle_log_details(Drv, Path, StartSha1, EndSha1, RelativeFilePath),
    {reply, Result, State};
handle_call({git_current_branch, Path}, _From,
            #state{port = Drv} = State) ->
    Result = handle_current_branch(Drv, Path),
    {reply, Result, State};
handle_call({git_list_branches, Path}, _From,
            #state{port = Drv} = State) ->
    Result = handle_list_branches(Drv, Path),
    {reply, Result, State};
handle_call({git_show, Path, GitObjectName}, _From,
            #state{port = Drv} = State) ->
    Result = handle_git_show(Drv, Path, GitObjectName),
    {reply, Result, State};
handle_call({git_revert, Path, RelativeFilePath}, _From,
            #state{port = Drv} = State) ->
    Result = handle_git_revert(Drv, Path, RelativeFilePath),
    {reply, Result, State};
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
handle_cast({write, Filename, Content}, State) ->
    handle_file_write(Filename, Content),
    {noreply, State};
handle_cast({commit, Filename, Content, Msg}, #state{port = Drv} = State) when
      Drv =/= undefined ->
    handle_file_write_and_commit(Drv, Filename, Content, Msg),
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

handle_file_write(Filename, Content) ->
    GitSourcePath = get_git_source_path(),
    AbsoluteFilename = filename:join([GitSourcePath, Filename]),
    git_save_file(AbsoluteFilename, Content).

handle_file_write_and_commit(Drv, Filename, Content, Msg) ->
    GitSourcePath = get_git_source_path(),
    AbsoluteFilename = filename:join([GitSourcePath, Filename]),
    ok = git_save_file(AbsoluteFilename, Content),
    ok = git_stage_file(Drv, GitSourcePath, AbsoluteFilename,
                       ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC),
    git_commit(Drv, GitSourcePath,
               Msg, ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

handle_status(Drv, Path) ->
    get_git_status(Drv, Path,
                   ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

handle_add(Drv, Path, RelativeFilePath) ->
    AbsoluteFilename = filename:join([Path, binary_to_list(RelativeFilePath)]),
    ok = git_stage_file(Drv, Path, AbsoluteFilename,
                        ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

handle_log(Drv, Path, HashType, RelativeFilePath) ->
    get_git_log(Drv, Path, HashType, RelativeFilePath,
                ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

handle_log_details(Drv, Path, RelativeFilePath) ->
    get_git_log_details(Drv, Path, RelativeFilePath,
                ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

handle_log_details(Drv, Path, StartSha1, EndSha1, RelativeFilePath) ->
    get_git_log_details(Drv, Path, StartSha1, EndSha1, RelativeFilePath,
                ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC).

-spec handle_current_branch(Drv :: alcove_drv:ref(), Path :: string()) -> binary().
handle_current_branch(Drv, Path) ->
    lager:debug("handle_current_branch(~p, ~p)", [Drv, Path]),
    Args = beamparticle_git_util:git_branch_command(list, current),
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC),
    lager:debug("current branch = ~p", [Content]),
    Content.

-spec handle_list_branches(Drv :: alcove_drv:ref(), Path :: string()) -> [map()].
handle_list_branches(Drv, Path) ->
    lager:debug("handle_list_branches(~p, ~p)", [Drv, Path]),
    Args = beamparticle_git_util:git_branch_command(list_branches),
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC),
    beamparticle_git_util:parse_git_list_branches(Content).

-spec handle_git_show(Drv :: alcove_drv:ref(), Path :: string(),
                      GitObjectName :: binary()) -> binary().
handle_git_show(Drv, Path, GitObjectName) ->
    lager:debug("handle_git_show(~p, ~p, ~p)", [Drv, Path, GitObjectName]),
    Args = [<<"show">>, GitObjectName],
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC),
    {ok, Content}.

-spec handle_git_revert(Drv :: alcove_drv:ref(), Path :: string(),
                        GitObjectName :: binary()) -> binary().
handle_git_revert(Drv, Path, GitObjectName) ->
    lager:debug("handle_git_revert(~p, ~p, ~p)", [Drv, Path, GitObjectName]),
    Args = [<<"reset">>, <<"HEAD">>, GitObjectName],
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        ?GIT_BACKEND_DEFAULT_COMMAND_TIMEOUT_MSEC),
    Content.

execute_command(Drv, Path, Command, Args, TimeoutMsec) ->
    {ok, ChildPID} = alcove:fork(Drv, []),
    alcove:chdir(Drv, [ChildPID], Path),
    EnvironmentVars = [],
    ok = alcove:execve(Drv, [ChildPID], Command, [Command | Args],
                       EnvironmentVars),
    lager:debug("git-backend running command ~s ~s", [Command, Args]),
    receive
        {alcove_event, Drv, [ChildPID], {exit_status, ExitCode}} = Event ->
            lager:debug("git-backend received event ~p", [Event]),
            Stdout = iolist_to_binary(alcove:stdout(Drv, [ChildPID])),
            Stderr = iolist_to_binary(alcove:stderr(Drv, [ChildPID])),
            {ExitCode, Stdout, Stderr}
    after
        TimeoutMsec ->
            alcove:kill(Drv, [], ChildPID, 9),
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
    Msg = <<"let the knowledge begin">>,
    AbsoluteFilename = filename:join([Path, "README.md"]),
    %% git_save_file(Drv, Path, AbsoluteFilename, Readme, Msg, TimeoutMsec).
    ok = git_save_file(AbsoluteFilename, Readme),
    ok = git_stage_file(Drv, Path, AbsoluteFilename, TimeoutMsec),
    git_commit(Drv, Path, Msg, TimeoutMsec).

git_add_branches(Drv, Path, Branches, TimeoutMsec) ->
    lists:foreach(fun(X) ->
                          {0, _, _} = execute_command(
                                        Drv, Path, ?GIT_BINARY,
                                        ["branch", X], TimeoutMsec)
                  end, Branches).

git_save_file(FullFilename, Content) ->
    lager:debug("git_save_file(~p)", [{FullFilename, Content}]),
    case file:write_file(FullFilename, Content) of
        ok ->
            FullPathStr = case is_binary(FullFilename) of
                              true -> binary_to_list(FullFilename);
                              false -> FullFilename
                          end,
            beamparticle_fake_inotify_server:event_close_write(FullPathStr),
            ok;
        E ->
            E
    end.

git_stage_file(Drv, Path, FullFilename, TimeoutMsec) ->
    lager:debug("git_stage_file(~p)", [{Drv, Path, FullFilename, TimeoutMsec}]),
    {0, _, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, ["add", FullFilename],
                  TimeoutMsec),
    ok.

git_commit(Drv, Path, Msg, TimeoutMsec) ->
    lager:debug("git_commit_file(~p)", [{Drv, Path, Msg, TimeoutMsec}]),
    case is_binary(Msg) of
        %% commit ony when a valid commit message is provided
        %% else just save to disk, which is done already
        true ->
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
            end;
        false ->
            ok
    end.

-spec get_git_status(Drv :: alcove_drv:ref(), Path :: binary(),
                     TimeoutMsec :: non_neg_integer()) -> map().
get_git_status(Drv, Path, TimeoutMsec) ->
    lager:debug("git_status(~p)", [{Drv, Path, TimeoutMsec}]),
    Args = beamparticle_git_util:git_status_command(),
    {0, StatusContent, _} = execute_command(
                  Drv, Path, ?GIT_BINARY, Args,
                  TimeoutMsec),
    beamparticle_git_util:parse_git_status(StatusContent).

-spec get_git_log(Drv :: alcove_drv:ref(),
                  Path :: binary(),
                  HashType :: short | long,
                  RelativeFilePath :: binary(),
                  TimeoutMsec :: non_neg_integer()) -> [binary()].
get_git_log(Drv, Path, HashType, RelativeFilePath, TimeoutMsec) ->
    lager:debug("get_git_log(~p)", [{Drv, HashType, RelativeFilePath, TimeoutMsec}]),
    Args = beamparticle_git_util:git_log_command(HashType, RelativeFilePath),
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        TimeoutMsec),
    lager:debug("Content = ~p", [Content]),
    binary:split(Content, <<"\0">>, [global, trim]).

-spec get_git_log_details(Drv :: alcove_drv:ref(),
                          Path :: binary(),
                          RelativeFilePath :: binary(),
                          TimeoutMsec :: non_neg_integer()) -> [map()].
get_git_log_details(Drv, Path, RelativeFilePath, TimeoutMsec) ->
    lager:debug("get_git_log_details(~p)", [{Drv, RelativeFilePath, TimeoutMsec}]),
    Args = beamparticle_git_util:git_log_details_command(RelativeFilePath),
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        TimeoutMsec),
    lager:debug("Content = ~p", [Content]),
    beamparticle_git_util:parse_git_log_details(Content).

-spec get_git_log_details(Drv :: alcove_drv:ref(),
                          Path :: binary(),
                          StartSha1 :: binary(),
                          EndSha1 :: binary(),
                          RelativeFilePath :: binary(),
                          TimeoutMsec :: non_neg_integer()) -> [map()].
get_git_log_details(Drv, Path, StartSha1, EndSha1, RelativeFilePath, TimeoutMsec) ->
    lager:debug("get_git_log_details(~p)", [{Drv, Path, StartSha1, EndSha1, RelativeFilePath, TimeoutMsec}]),
    Args = beamparticle_git_util:git_log_details_command(StartSha1, EndSha1, RelativeFilePath),
    {0, Content, _} = execute_command(
                        Drv, Path, ?GIT_BINARY, Args,
                        TimeoutMsec),
    lager:debug("Content = ~p", [Content]),
    beamparticle_git_util:parse_git_log_details(Content).

-spec get_git_source_path() -> string().
get_git_source_path() ->
    GitBackendConfig = application:get_env(?APPLICATION_NAME, gitbackend, []),
    RootPath = proplists:get_value(rootpath, GitBackendConfig, "git-data"),
    FullRootPath = filename:absname(RootPath),
    filename:join([FullRootPath, "git-src"]).

