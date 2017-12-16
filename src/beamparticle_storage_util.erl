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
-module(beamparticle_storage_util).
-author("neerajsharma").

-include("beamparticle_constants.hrl").

%% API

-export([
  read/1,
  write/2,
  delete/1,
  lapply/2,
  read/2,
  write/3,
  write/4,
  delete/2,
  lapply/3,
  get_key_prefix/2,
  extract_key/2
]).

-export([get_non_self_pid/0]).

-export([list_functions/1, similar_functions/1, similar_functions_with_doc/1,
         function_history/1, similar_function_history/1]).
-export([create_function_snapshot/0, export_functions/2,
         get_function_snapshots/0, import_functions/2]).
-export([create_function_history_snapshot/0, export_functions_history/2,
         get_function_history_snapshots/0, import_functions_history/1]).

%% whatis functionality conviniently exposed
-export([list_whatis/1, similar_whatis/1]).
-export([create_whatis_snapshot/0, get_whatis_snapshots/0,
         export_whatis/2,
        import_whatis/2]).

-export([list_job/1, similar_job/1]).
-export([create_job_snapshot/0, get_job_snapshots/0,
         export_job/2,
        import_job/2]).

-export([reindex_function_usage/1,
        function_deps/1,
        function_uses/1]).

-type container_t() :: function | function_history
                        | function_deps | function_uses
                        | intent_logic | job | pool | user | whatis.

-export_type([container_t/0]).

%% Custom APIs

-define(POOL, beamparticle_k_model_pool).
-define(INTENT_LOGIC_PREFIX, <<"intentlogic--">>).
-define(FUNCTION_PREFIX, <<"fun--">>).
-define(FUNCTION_HISTORY_PREFIX, <<"funh--">>).
-define(FUNCTION_DEPS_PREFIX, <<"fundp--">>).
-define(FUNCTION_USED_PREFIX, <<"funud--">>).
-define(JOB_PREFIX, <<"job--">>).
-define(POOL_PREFIX, <<"pool--">>).
-define(USER_PREFIX, <<"user--">>).
-define(WHATIS_PREFIX, <<"whatis--">>).
-define(DATA_PREFIX, <<"data--">>).

-spec read(binary()) -> {ok, binary()} | {error, not_found}.
read(Key) ->
    Pid = get_non_self_pid(),
    leveldbstore_proc:read(Pid, Key, nostate).

-spec write(binary(), binary()) -> boolean().
write(Key, Value) when is_binary(Key) andalso is_binary(Value) ->
    Pid = get_non_self_pid(),
    leveldbstore_proc:update(Pid, Key, Value, nostate).

-spec delete(binary()) -> boolean().
delete(Key) ->
    Pid = get_non_self_pid(),
    leveldbstore_proc:delete(Pid, Key, nostate).

-spec lapply(fun(({binary(), binary()}, {term(), term()}) -> term()),
            binary()) -> {ok, term()} | {error, term()}.
lapply(Fun, KeyPrefix) ->
    Pid = get_non_self_pid(),
    leveldbstore_proc:lapply(Pid, Fun, KeyPrefix, nostate).

-spec read(binary(), container_t()) -> {ok, binary()} | {error, not_found}.
read(Key, Type) ->
    read(get_key_prefix(Key, Type)).

-spec write(binary(), binary(), container_t(), boolean()) -> boolean().
write(Key, Value, function, CreateHistory) ->
    %% invalidate cache upon change
    beamparticle_cache_util:async_remove(Key),
    case CreateHistory of
        true ->
            %% Save history
            {Uuid, _} = uuid:get_v1(uuid:new(self(), erlang)),
            UuidHexBin = beamparticle_util:bin_to_hex_binary(Uuid),
            HistoryKey = iolist_to_binary([get_key_prefix(Key, function_history), <<"-">>, UuidHexBin]),
            write(HistoryKey, Value);
        false ->
            ok
    end,
    %% extract old version of code which was saved earlier
    %% so as to remove uses (see update_function_call_tree/5 below)
    OldBody = case read(Key, function) of
                  {ok, V} ->
                      V;
                  _ ->
                      <<>>
              end,
    %% Save current value
    case write(get_key_prefix(Key, function), Value) of
        true ->
            %% reindex the function
            FullFunctionName = Key,
            [FunctionName, ArityBin] = binary:split(Key, <<"/">>),
            update_function_call_tree(FullFunctionName, FunctionName, ArityBin, Value, OldBody),
            true;
        false ->
            false
    end;
write(Key, Value, Type, _) ->
    write(get_key_prefix(Key, Type), Value).

-spec write(binary(), binary(), container_t()) -> boolean().
write(Key, Value, Type) ->
    %% write with history if applicable
    write(Key, Value, Type, true).

-spec delete(binary(), container_t()) -> boolean().
delete(Key, function) ->
    %% invalidate cache upon change
    beamparticle_cache_util:async_remove(Key),
    %% extract old version of code which was saved earlier
    %% so as to remove uses (see update_function_call_tree/5 below)
    OldBody = case read(Key, function) of
                  {ok, V} ->
                      V;
                  _ ->
                      <<>>
              end,
    NewBody = <<>>,
    %% reindex the function
    FullFunctionName = Key,
    [FunctionName, ArityBin] = binary:split(Key, <<"/">>),
    update_function_call_tree(FullFunctionName, FunctionName, ArityBin, NewBody, OldBody),
    delete(Key, function_deps),
    %% dont remove function history
    delete(get_key_prefix(Key, function));
delete(Key, Type) ->
    delete(get_key_prefix(Key, Type)).

-spec lapply(fun(({binary(), binary()}, {term(), term()}) -> term()),
            binary(), container_t()) ->
    {ok, term()} | {error, term()}.
lapply(Fun, KeyPrefix, Type) ->
    lapply(Fun, get_key_prefix(KeyPrefix, Type)).

%% @doc Get pid which is different from self(), else deadlock
%%
%% This function shall be used to get worker pid which is
%% different from self(), so as to avoid deadlock when
%% read/write/.. functions are used within lapply,
%% which will deadlock when trying to do gen_server:call/3
%% to itself back again.
%%
%% Note that when the number of pool workers is set to 1
%% then there is no way to avoid the deadlock, so then
%% this function shall always return {error, single_worker}.
%%
%% Change the configuration to have at least more than 1 worker.
-spec get_non_self_pid() -> pid() | {error, single_worker}.
get_non_self_pid() ->
    Pid = leveldbstore_proc:get_pid(?POOL),
    case self() =:= Pid of
        true ->
            P2 = leveldbstore_proc:get_pid(?POOL),
            case self() =:= P2 of
                true ->
                    {error, single_worker};
                false ->
                    P2
            end;
        false ->
            Pid
    end.

%% @doc Get similar function with first line of doc
-spec similar_functions_with_doc(FunctionPrefix :: binary()) -> [{binary(), binary()}].
similar_functions_with_doc(FunctionPrefix) ->
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         FirstComment = case lists:reverse(erl_comment_scan:scan_lines(binary_to_list(V))) of
                                            [] ->
                                                <<"">>;
                                            [H | _] ->
                                                H
                                        end,
                         {[{ExtractedKey, FirstComment} | R], S2};
                     _ ->
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, function),
	Resp.

-spec list_functions(StartingFunctionPrefix :: binary()) -> [binary()].
list_functions(StartingFunctionPrefix) ->
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         throw({{ok, R}, S2});
                     ExtractedKey ->
                         {[ExtractedKey | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, StartingFunctionPrefix, function),
	Resp.

-spec similar_functions(FunctionPrefix :: binary()) -> [binary()].
similar_functions(FunctionPrefix) ->
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         {[ExtractedKey | R], S2};
                     _ ->
                         %% prefix no longer met, so return
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, function),
	Resp.

-spec function_history(FunctionNameWithArity :: binary()) -> [binary()].
function_history(FunctionNameWithArity) ->
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function_history) of
                     undefined ->
                         throw({{ok, R}, S2});
                     ExtractedKey ->
                         {[ExtractedKey | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, <<FunctionNameWithArity/binary, "-">>, function_history),
	Resp.

-spec similar_function_history(FunctionPrefix :: binary()) -> [binary()].
similar_function_history(FunctionPrefix) ->
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function_history) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         {[ExtractedKey | R], S2};
                     _ ->
                         %% prefix no longer met, so return
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, FunctionPrefix, function_history),
	Resp.

%%
%% Function snapshot management
%%

-spec create_function_snapshot() -> {ok, TarGzFilename :: string()}.
create_function_snapshot() ->
    SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
    KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
    {{Year, Month, Day}, {_Hour, _Min, _Sec}} = calendar:now_to_datetime(erlang:timestamp()),
    Folder = io_lib:format("~s/~p_~p_~p",
                           [KnowledgeRoot, Year, Month, Day]),
    export_functions(<<>>, Folder),
    %% Get file names with folder
    Filenames = filelib:wildcard(Folder ++ "/*.erl.fun"),
    TarGzFilename = io_lib:format("~s/~p_~p_~p__archive.tar.gz",
                                                                 [KnowledgeRoot, Year, Month, Day]),
    ok = erl_tar:create(TarGzFilename, Filenames, [compressed]),
    lists:foreach(fun(E) -> file:delete(E) end, Filenames),
    file:del_dir(Folder),
    {ok, TarGzFilename}.

-spec export_functions(FunctionPrefix :: binary(), Folder :: string()) ->
    ok | {error, term()}.
export_functions(FunctionPrefix, Folder) ->

    lager:info("export_functions(~p, ~s)", [FunctionPrefix, Folder]),
    case filelib:ensure_dir(Folder ++ "/") of
        ok ->
            Fn = fun({K, V}, AccIn) ->
                         {R, S2} = AccIn,
                         case beamparticle_storage_util:extract_key(K, function) of
                             undefined ->
                                 throw({{ok, R}, S2});
                             ExtractedKey ->
                                 try
                                     [FunctionName, Arity] = binary:split(ExtractedKey, <<"/">>),
                                     Filename = io_lib:format("~s/~s-~s.erl.fun",
                                                              [Folder, FunctionName,
                                                               Arity]),
                                     lager:debug("Function saved at ~s", [Filename]),
                                     file:write_file(Filename, V),
                                     {R, S2}
                                 catch
                                     Class:Reason ->
                                         Stacktrace = erlang:get_stacktrace(),
                                         lager:error("Error while exporting function ~p:~p, stacktrace = ~p", [Class, Reason, Stacktrace]),
                                         {R, S2}
                                 end
                         end
                 end,
            beamparticle_storage_util:lapply(Fn, FunctionPrefix, function);
        E ->
            E
    end.

-spec get_function_snapshots() -> [binary()].
get_function_snapshots() ->
	SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
	KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
	%% Get file names alone
    TarGzFilenames = filelib:wildcard(KnowledgeRoot ++ "/*_archive.tar.gz"),
    lists:reverse(lists:foldl(fun(E, AccIn) ->
                        [_, Name] = string:split(E, "/", trailing),
                        [Name | AccIn]
                end, [], TarGzFilenames)).


-spec import_functions(file | network, TarGzFilename :: string()) -> ok | {error, term()}.
import_functions(file, TarGzFilename) ->
	SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
	KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
	%% Get file names alone
    FullTarGzFilename = KnowledgeRoot ++ "/" ++ TarGzFilename,
    lager:debug("FullTarGzFilename = ~s", [FullTarGzFilename]),
    case erl_tar:extract(FullTarGzFilename, [compressed]) of
        ok ->
            {ok, Filenames} = erl_tar:table(FullTarGzFilename, [compressed]),
            lists:foreach(fun(E) ->
                                  lager:debug("Importing knowledge file ~s", [E]),
                                  case filelib:is_regular(E) of
                                      true ->
                                          {ok, Data} = file:read_file(E),
                                          [_, Name] = string:split(E, "/", trailing),
                                          [NameOnly, NameRest] = string:split(Name, "-", trailing),
                                          [Arity, _] = string:split(NameRest, "."),
                                          CreateHistory = false,
                                          write(list_to_binary(NameOnly ++ "/" ++ Arity),
                                                Data, function, CreateHistory);
                                      false ->
                                          ok
                                  end
                          end, Filenames),
            lists:foreach(fun(E) -> file:delete(E) end, Filenames),
            ok;
        E ->
            E
    end;
import_functions(network, {Url, SkipIfExistsFunctions}) when
      is_list(Url) andalso is_list(SkipIfExistsFunctions) ->
    import_functions(network, {Url, [], SkipIfExistsFunctions});
import_functions(network, {Url, UrlHeaders, SkipIfExistsFunctions}) when
      is_list(Url) andalso is_list(SkipIfExistsFunctions) ->
    case httpc:request(get, {Url, UrlHeaders}, [], [{body_format, binary}]) of
      {ok, {{_, 200, _}, _Headers, Body}} ->
          case erl_tar:extract({binary, Body}, [compressed, memory]) of
              {error, E} ->
                  {error, E};
              {ok, TarResp} ->
                  lists:foreach(fun({Filename, Data}) ->
                                        lager:debug("Filename = ~p", [Filename]),
                                        Extension = filename:extension(Filename),
                                        FileBasename = filename:basename(Filename, Extension),
                                        BaseNameExtension = filename:extension(FileBasename),
                                        TrueFileBasename = filename:basename(FileBasename, BaseNameExtension),
                                        case {BaseNameExtension, Extension} of
                                            {".erl", ".fun"} ->
                                                [_, Name] = string:split(Filename, "/", trailing),
                                                [NameOnly, NameRest] = string:split(Name, "-", trailing),
                                                [Arity, _] = string:split(NameRest, "."),
                                                NameWithArity = list_to_binary(NameOnly ++ "/" ++ Arity),
                                                IsSkipped = case lists:member(TrueFileBasename, SkipIfExistsFunctions) of
                                                                true ->
                                                                    case read(NameWithArity, function) of
                                                                        {error, _} ->
                                                                            %% write if none exists
                                                                            false;
                                                                        _ ->
                                                                            true
                                                                    end;
                                                                false ->
                                                                    false
                                                            end,
                                                case IsSkipped of
                                                    false ->
                                                        lager:debug("Importing knowledge file ~s", [Filename]),
                                                        CreateHistory = true,
                                                        write(NameWithArity, Data, function, CreateHistory);
                                                    true ->
                                                        lager:info("Skipping as per policy, file = ~p", [Filename]),
                                                        ok
                                                end;
                                            ExtCombo ->
                                                %% ignore
                                                lager:debug("Ignoring extension = ~p", [ExtCombo]),
                                                ok
                                        end
                                end, TarResp),
                  ok
          end;
      Resp ->
          {error, Resp}
	end.

%%
%% Function history snapshot management
%%

-spec create_function_history_snapshot() -> {ok, TarGzFilename :: string()}.
create_function_history_snapshot() ->
    SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
    KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
    {{Year, Month, Day}, {_Hour, _Min, _Sec}} = calendar:now_to_datetime(erlang:timestamp()),
    Folder = io_lib:format("~s/history/~p_~p_~p",
                           [KnowledgeRoot, Year, Month, Day]),
    export_functions_history(<<>>, Folder),
    %% Get file names with folder
    Filenames = filelib:wildcard(Folder ++ "/*.erl.fun"),
    TarGzFilename = io_lib:format("~s/~p_~p_~p_archive_history.tar.gz",
                                                                 [KnowledgeRoot, Year, Month, Day]),
    ok = erl_tar:create(TarGzFilename, Filenames, [compressed]),
    lists:foreach(fun(E) -> file:delete(E) end, Filenames),
    file:del_dir(Folder),
    {ok, TarGzFilename}.

-spec export_functions_history(FunctionPrefix :: binary(), Folder :: string()) ->
    ok | {error, term()}.
export_functions_history(FunctionPrefix, Folder) ->

    lager:info("export_functions_history(~p, ~s)", [FunctionPrefix, Folder]),
    case filelib:ensure_dir(Folder ++ "/") of
        ok ->
            Fn = fun({K, V}, AccIn) ->
                         {R, S2} = AccIn,
                         case beamparticle_storage_util:extract_key(K, function_history) of
                             undefined ->
                                 throw({{ok, R}, S2});
                             ExtractedKey ->
                                 try
                                     lager:debug("History Key = ~p", [ExtractedKey]),
                                     [FunctionName, RestFunctionName] = binary:split(ExtractedKey, <<"/">>),
                                     [Arity, Uuidv1] = binary:split(RestFunctionName, <<"-">>),
                                     Filename = io_lib:format("~s/~s-~s-~s.erl.fun",
                                                              [Folder, FunctionName,
                                                               Arity, Uuidv1]),
                                     lager:debug("Function saved at ~s", [Filename]),
                                     file:write_file(Filename, V),
                                     {R, S2}
                                 catch
                                     Class:Reason ->
                                         Stacktrace = erlang:get_stacktrace(),
                                         lager:error("Error while exporting function history ~p:~p, stacktrace = ~p", [Class, Reason, Stacktrace]),
                                         {R, S2}
                                 end
                         end
                 end,
            beamparticle_storage_util:lapply(Fn, FunctionPrefix, function_history);
        E ->
            E
    end.

-spec get_function_history_snapshots() -> [binary()].
get_function_history_snapshots() ->
	SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
	KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
	%% Get file names alone
    TarGzFilenames = filelib:wildcard(KnowledgeRoot ++ "/*_archive_history.tar.gz"),
    lists:reverse(lists:foldl(fun(E, AccIn) ->
                        [_, Name] = string:split(E, "/", trailing),
                        [Name | AccIn]
                end, [], TarGzFilenames)).


-spec import_functions_history(TarGzFilename :: string()) -> ok | {error, term()}.
import_functions_history(TarGzFilename) ->
	SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
	KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
	%% Get file names alone
    FullTarGzFilename = KnowledgeRoot ++ "/" ++ TarGzFilename,
    lager:debug("FullTarGzFilename = ~s", [FullTarGzFilename]),
    case erl_tar:extract(FullTarGzFilename, [compressed]) of
        ok ->
            {ok, Filenames} = erl_tar:table(FullTarGzFilename, [compressed]),
            lists:foreach(fun(E) ->
                                  lager:debug("Importing knowledge history file ~s", [E]),
                                  case filelib:is_regular(E) of
                                      true ->
                                          {ok, Data} = file:read_file(E),
                                          [_, Name] = string:split(E, "/", trailing),
                                          [NameOnly, NameRest] = string:split(Name, "-"),
                                          [ArityWithUuidv1, _] = string:split(NameRest, "."),
                                          write(list_to_binary(NameOnly ++ "/" ++ ArityWithUuidv1),
                                                Data, function_history);
                                      false ->
                                          ok
                                  end
                          end, Filenames),
            lists:foreach(fun(E) -> file:delete(E) end, Filenames),
            ok;
        E ->
            E
    end.

%%
%% whatis snapshot management
%%

-spec list_whatis(StartingPrefix :: binary()) -> [binary()].
list_whatis(StartingPrefix) ->
    list_generic(StartingPrefix, whatis).

-spec similar_whatis(Prefix :: binary()) -> [binary()].
similar_whatis(Prefix) ->
    similar_generic(Prefix, whatis).

-spec create_whatis_snapshot() -> {ok, TarGzFilename :: string()}.
create_whatis_snapshot() ->
    create_generic_snapshot(whatis, <<"html">>, false).

-spec export_whatis(Prefix :: binary(), Folder :: string()) ->
    ok | {error, term()}.
export_whatis(Prefix, Folder) ->
    export_generic(Prefix, Folder, whatis, <<"html">>, false).

-spec get_whatis_snapshots() -> [binary()].
get_whatis_snapshots() ->
    get_generic_snapshots(whatis).

-spec import_whatis(file | network, TarGzFilename :: string()) -> ok | {error, term()}.
import_whatis(file, TarGzFilename) ->
    import_generic(file, TarGzFilename, whatis, {"", ".html"}, false);
import_whatis(network, Args) ->
    import_generic(network, Args, whatis, {"", ".html"}, false).

%%
%% job snapshot management
%%

-spec list_job(StartingPrefix :: binary()) -> [binary()].
list_job(StartingPrefix) ->
    list_generic(StartingPrefix, job).

-spec similar_job(Prefix :: binary()) -> [binary()].
similar_job(Prefix) ->
    similar_generic(Prefix, job).

-spec create_job_snapshot() -> {ok, TarGzFilename :: string()}.
create_job_snapshot() ->
    create_generic_snapshot(job, <<"job.bin">>, true).

-spec export_job(Prefix :: binary(), Folder :: string()) ->
    ok | {error, term()}.
export_job(Prefix, Folder) ->
    export_generic(Prefix, Folder, job, <<"job.bin">>, true).

-spec get_job_snapshots() -> [binary()].
get_job_snapshots() ->
    get_generic_snapshots(job).

-spec import_job(file | network, TarGzFilename :: string()) -> ok | {error, term()}.
import_job(file, TarGzFilename) ->
    import_generic(file, TarGzFilename, job, {".job", ".bin"}, true);
import_job(network, Args) ->
    import_generic(network, Args, job, {".job", ".bin"}, true).

%%
%% generic snapshot management
%%

-spec list_generic(StartingPrefix :: binary(), Type :: atom()) -> [binary()].
list_generic(StartingPrefix, Type) ->
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, Type) of
                     undefined ->
                         throw({{ok, R}, S2});
                     ExtractedKey ->
                         {[ExtractedKey | R], S2}
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, StartingPrefix, Type),
	Resp.

-spec similar_generic(Prefix :: binary(), Type :: atom()) -> [binary()].
similar_generic(Prefix, Type) ->
    PrefixLen = byte_size(Prefix),
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, Type) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<Prefix:PrefixLen/binary, _/binary>> = ExtractedKey ->
                         {[ExtractedKey | R], S2};
                     _ ->
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, Prefix, Type),
	Resp.

-spec create_generic_snapshot(Type :: atom(), TypExt :: binary(), IsUuidKey :: boolean()) -> {ok, TarGzFilename :: string()}.
create_generic_snapshot(Type, TypeExt, IsUuidKey) ->
    SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
    KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
    {{Year, Month, Day}, {_Hour, _Min, _Sec}} = calendar:now_to_datetime(erlang:timestamp()),
    TypeBin = atom_to_binary(Type, utf8),
    Folder = io_lib:format("~s/~s/~p_~p_~p",
                           [KnowledgeRoot, TypeBin, Year, Month, Day]),
    export_generic(<<>>, Folder, Type, TypeExt, IsUuidKey),
    %% Get file names with folder
    WildCardPattern = Folder ++ io_lib:format("/~s_*.~s", [TypeBin, TypeExt]),
    Filenames = filelib:wildcard(WildCardPattern),
    TarGzFilename = io_lib:format("~s/~p_~p_~p_archive_~s.tar.gz",
                                  [KnowledgeRoot, Year, Month, Day, TypeBin]),
    ok = erl_tar:create(TarGzFilename, Filenames, [compressed]),
    lists:foreach(fun(E) -> file:delete(E) end, Filenames),
    file:del_dir(Folder),
    {ok, TarGzFilename}.

-spec export_generic(Prefix :: binary(), Folder :: string(), Type :: atom(), TypeExt :: binary(), IsUuidKey :: boolean()) ->
    ok | {error, term()}.
export_generic(Prefix, Folder, Type, TypeExt, IsUuidKey) ->
    lager:info("export_generic(~p, ~s, ~p)", [Prefix, Folder, Type]),
    case filelib:ensure_dir(Folder ++ "/") of
        ok ->
            Fn = fun({K, V}, AccIn) ->
                         {R, S2} = AccIn,
                         case beamparticle_storage_util:extract_key(K, Type) of
                             undefined ->
                                 throw({{ok, R}, S2});
                             ExtractedKey ->
                                 try
                                     Name = case IsUuidKey of
                                                true ->
                                                    beamparticle_util:bin_to_hex_binary(ExtractedKey);
                                                false ->
                                                    ExtractedKey
                                            end,
                                     Filename = io_lib:format("~s/~p_~s.~s",
                                                              [Folder, Type, Name, TypeExt]),
                                     lager:debug("~p saved at ~s", [Type, Filename]),
                                     file:write_file(Filename, V),
                                     {R, S2}
                                 catch
                                     Class:Reason ->
                                         Stacktrace = erlang:get_stacktrace(),
                                         lager:error("Error while exporting ~p ~p:~p, stacktrace = ~p", [Type, Class, Reason, Stacktrace]),
                                         {R, S2}
                                 end
                         end
                 end,
            beamparticle_storage_util:lapply(Fn, Prefix, Type);
        E ->
            E
    end.

-spec get_generic_snapshots(Type :: atom()) -> [binary()].
get_generic_snapshots(Type) ->
	SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
	KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
	%% Get file names alone
    WildCard = KnowledgeRoot ++ io_lib:format("/*_archive_~p.tar.gz", [Type]),
    TarGzFilenames = filelib:wildcard(WildCard),
    lists:reverse(lists:foldl(fun(E, AccIn) ->
                        [_, Name] = string:split(E, "/", trailing),
                        [Name | AccIn]
                end, [], TarGzFilenames)).

-spec import_generic(file | network, TarGzFilename :: string(), Type :: atom(), TypeExtTuple :: {Ext1 :: string(), Ext2 :: string()}, IsUuidKey :: boolean()) -> ok | {error, term()}.
import_generic(file, TarGzFilename, Type, _TypeExtTuple, IsUuidKey) ->
    [_First, LastPart] = string:split(TarGzFilename, "_", trailing),
    TypeStr = atom_to_list(Type),
    case string:split(LastPart, ".") of
        [TypeStr, _] ->
            SnapshotConfig = application:get_env(?APPLICATION_NAME, snapshot, []),
            KnowledgeRoot = proplists:get_value(knowledge_root, SnapshotConfig, "knowledge"),
            %% Get file names alone
            FullTarGzFilename = KnowledgeRoot ++ "/" ++ TarGzFilename,
            lager:debug("FullTarGzFilename = ~s", [FullTarGzFilename]),
            case erl_tar:extract(FullTarGzFilename, [compressed]) of
                ok ->
                    {ok, Filenames} = erl_tar:table(FullTarGzFilename, [compressed]),
                    lists:foreach(fun(E) ->
                                          lager:debug("Importing ~p file ~s", [Type, E]),
                                          case filelib:is_regular(E) of
                                              true ->
                                                  {ok, Data} = file:read_file(E),
                                                  [_, Name] = string:split(E, "/", trailing),
                                                  case string:split(Name, "_") of
                                                      [TypeStr, NameWithExt] ->
                                                          [NameOnly, _] = string:split(NameWithExt, "."),
                                                          NameOnlyBin = list_to_binary(NameOnly),
                                                          KeyName = case IsUuidKey of
                                                                        true ->
                                                                            beamparticle_util:hex_binary_to_bin(NameOnlyBin);
                                                                        false ->
                                                                            NameOnlyBin
                                                                    end,
                                                          CreateHistory = true,
                                                          write(KeyName, Data, Type, CreateHistory);
                                                      _ ->
                                                          lager:warning("Skip imporing file ~s because its not ~p", [E, Type]),
                                                          ok
                                                  end;
                                              false ->
                                                  ok
                                          end
                                  end, Filenames),
                    lists:foreach(fun(E) -> file:delete(E) end, Filenames),
                    ok;
                E ->
                    E
            end;
        _ ->
            {error, <<"not a valid archive">>}
    end;
import_generic(network, {Url, SkipIfExistsFunctions}, Type, TypeExtTuple, IsUuidKey) when
      is_list(Url) andalso is_list(SkipIfExistsFunctions) ->
    import_generic(network, {Url, [], SkipIfExistsFunctions}, Type, TypeExtTuple, IsUuidKey);
import_generic(network, {Url, UrlHeaders, SkipIfExistsFunctions}, Type, TypeExtTuple, IsUuidKey) when
      is_list(Url) andalso is_list(SkipIfExistsFunctions) ->
    case httpc:request(get, {Url, UrlHeaders}, [], [{body_format, binary}]) of
      {ok, {{_, 200, _}, _Headers, Body}} ->
          case erl_tar:extract({binary, Body}, [compressed, memory]) of
              {error, E} ->
                  {error, E};
              {ok, TarResp} ->
                  lists:foreach(fun({Filename, Data}) ->
                                        lager:debug("Filename = ~p", [Filename]),
                                        Extension = filename:extension(Filename),
                                        FileBasename = filename:basename(Filename, Extension),
                                        BaseNameExtension = filename:extension(FileBasename),
                                        %% TrueFileBasename = filename:basename(FileBasename, BaseNameExtension),
                                        TypeStr = atom_to_list(Type),
                                        case {BaseNameExtension, Extension} of
                                            TypeExtTuple ->
                                                [_, Name] = string:split(Filename, "/", trailing),
                                                case string:split(Name, "_") of
                                                    [TypeStr, NameWithExt] ->
                                                        [NameOnly, _] = string:split(NameWithExt, "."),
                                                        NameOnlyBin = list_to_binary(NameOnly),
                                                        KeyName = case IsUuidKey of
                                                                      true ->
                                                                          beamparticle_util:hex_binary_to_bin(NameOnlyBin);
                                                                      false ->
                                                                          NameOnlyBin
                                                                  end,
                                                        %%case read(KeyName, Type) of
                                                        %%    {error, _} ->
                                                                %% write if none exists
                                                                lager:debug("Importing ~p file ~s", [Type, Filename]),
                                                                CreateHistory = true,
                                                                write(KeyName, Data, Type, CreateHistory);
                                                        %%    _ ->
                                                        %%        lager:info("Skipping as per policy, file = ~p", [Filename]),
                                                        %%        ok
                                                        %%end;
                                                    _ ->
                                                        lager:warning("Skip imporing file ~s because its not ~p", [Filename, Type]),
                                                        ok
                                                end;
                                            ExtCombo ->
                                                %% ignore
                                                lager:debug("Ignoring extension = ~p", [ExtCombo]),
                                                ok
                                        end
                                end, TarResp),
                  ok
          end;
      Resp ->
          {error, Resp}
	end.

%%
%% Function usage
%%

-spec reindex_function_usage(FunctionPrefix :: binary()) ->
    ok | {error, term()}.
reindex_function_usage(FunctionPrefix) ->
    lager:info("reindex_function_usage(~p)", [FunctionPrefix]),
    FunctionPrefixLen = byte_size(FunctionPrefix),
    Fn = fun({K, V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, function) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<FunctionPrefix:FunctionPrefixLen/binary, _/binary>> = ExtractedKey ->
                         try
                             [FunctionName, ArityBin] = binary:split(ExtractedKey, <<"/">>),
                             update_function_call_tree(ExtractedKey, FunctionName, ArityBin, V, <<>>),
                             lager:debug("Function reindexed ~s", [ExtractedKey]),
                             {R, S2}
                         catch
                             Class:Reason ->
                                 Stacktrace = erlang:get_stacktrace(),
                                 lager:error("Error while reindex_function_usage ~p:~p, stacktrace = ~p", [Class, Reason, Stacktrace]),
                                 {R, S2}
                         end;
                     _ ->
                         throw({{ok, R}, S2})
                 end
         end,
    beamparticle_storage_util:lapply(Fn, FunctionPrefix, function),
    ok.

update_function_call_tree(FullFunctionName, FunctionName, ArityBin, NewBody, OldBody)
    when is_binary(FunctionName) andalso is_binary(ArityBin)
        andalso is_binary(NewBody) andalso is_binary(OldBody) ->
    Arity = binary_to_integer(ArityBin),
    update_function_call_tree(FullFunctionName, FunctionName, Arity, NewBody, OldBody);
update_function_call_tree(FullFunctionName, FunctionName, Arity, NewBody, OldBody)
    when is_binary(FunctionName) andalso is_integer(Arity)
        andalso is_binary(NewBody) andalso is_binary(OldBody) ->

    %% Remove references with respect to Old Code
    remove_function_references(FunctionName, Arity, OldBody),
    add_function_references(FullFunctionName, FunctionName, Arity, NewBody),
    ok.

-spec add_function_references(binary(), binary(), integer(), binary()) -> ok.
add_function_references(_FullFunctionName, _FunctionName, _Arity, <<>>) ->
    ok;
add_function_references(FullFunctionName, FunctionName, Arity, NewBody) ->
    FunctionCalls =
       beamparticle_erlparser:discover_function_calls(NewBody),
    lager:debug("~p calls ~p", [FullFunctionName, FunctionCalls]),
    FunctionCallsBin = sext:encode(FunctionCalls),
    beamparticle_storage_util:write(
        FullFunctionName, FunctionCallsBin, function_deps),
    lists:foreach(fun(E) ->
                          FunFullnameBin = case E of
                                               {FunNameBin, FunArity} ->
                                                   FunArityBin = integer_to_binary(FunArity),
                                                   iolist_to_binary([FunNameBin, <<"/">>,
                                                                     FunArityBin]);
                                               {ModNameBin, FunNameBin, FunArity} ->
                                                   FunArityBin = integer_to_binary(FunArity),
                                                   iolist_to_binary([ModNameBin, <<":">>,
                                                                     FunNameBin, <<"/">>,
                                                                     FunArityBin])
                                           end,
                          case beamparticle_storage_util:read(FunFullnameBin, function_uses) of
                              {ok, FunCallsBin} ->
                                  FunCalls = sext:decode(FunCallsBin),
                                  UpdatedFunCalls = [{FunctionName, Arity} | FunCalls],
                                  UniqUpdatedFunCalls = lists:usort(UpdatedFunCalls),
                                  UpdatedFunCallsBin = sext:encode(UniqUpdatedFunCalls),
                                  beamparticle_storage_util:write(FunFullnameBin, UpdatedFunCallsBin, function_uses);
                              {error, _} ->
                                  FunCalls = [{FunctionName, Arity}],
                                  FunCallsBin = sext:encode(FunCalls),
                                  beamparticle_storage_util:write(FunFullnameBin, FunCallsBin, function_uses)
                          end
                  end, FunctionCalls),
    ok.

-spec remove_function_references(binary(), integer(), binary()) -> ok.
remove_function_references(_FunctionName, _Arity, <<>>) ->
    ok;
remove_function_references(FunctionName, Arity, OldBody) ->
    OldFunctionCalls =
       beamparticle_erlparser:discover_function_calls(OldBody),
    lists:foreach(fun(E) ->
                          FunFullnameBin = case E of
                                               {FunNameBin, FunArity} ->
                                                   FunArityBin = integer_to_binary(FunArity),
                                                   iolist_to_binary([FunNameBin, <<"/">>,
                                                                     FunArityBin]);
                                               {ModNameBin, FunNameBin, FunArity} ->
                                                   FunArityBin = integer_to_binary(FunArity),
                                                   iolist_to_binary([ModNameBin, <<":">>,
                                                                     FunNameBin, <<"/">>,
                                                                     FunArityBin])
                                           end,
                          case beamparticle_storage_util:read(FunFullnameBin, function_uses) of
                              {ok, FunCallsBin} ->
                                  FunCalls = sext:decode(FunCallsBin),
                                  UpdatedFunCalls = lists:delete({FunctionName, Arity}, FunCalls),
                                  UpdatedFunCallsBin = sext:encode(UpdatedFunCalls),
                                  beamparticle_storage_util:write(FunFullnameBin, UpdatedFunCallsBin, function_uses);
                              {error, _} ->
                                  ok
                          end
                  end, OldFunctionCalls),
    ok.

function_deps(FullFunctionName) when is_binary(FullFunctionName) ->
    case beamparticle_storage_util:read(FullFunctionName, function_deps) of
        {ok, FunCallsBin} ->
            {ok, sext:decode(FunCallsBin)};
        E ->
            E
    end.

function_uses(FullFunctionName) when is_binary(FullFunctionName) ->
    case beamparticle_storage_util:read(FullFunctionName, function_uses) of
        {ok, FunCallsBin} ->
            {ok, sext:decode(FunCallsBin)};
        E ->
            E
    end.

-spec get_key_prefix(binary(), container_t()) -> binary().
get_key_prefix(Key, function) ->
    <<?FUNCTION_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, function_history) ->
    <<?FUNCTION_HISTORY_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, function_deps) ->
    <<?FUNCTION_DEPS_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, function_uses) ->
    <<?FUNCTION_USED_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, intent_logic) ->
    <<?INTENT_LOGIC_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, job) ->
    <<?JOB_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, pool) ->
    <<?POOL_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, user) ->
    <<?USER_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, whatis) ->
    <<?WHATIS_PREFIX/binary, Key/binary>>;
get_key_prefix(Key, data) ->
    <<?DATA_PREFIX/binary, Key/binary>>.

-spec extract_key(binary(), container_t()) -> binary() | undefined.
extract_key(<<"fun--", Key/binary>>, function) ->
    Key;
extract_key(<<"funh--", Key/binary>>, function_history) ->
    Key;
extract_key(<<"fundp--", Key/binary>>, function_deps) ->
    Key;
extract_key(<<"funud--", Key/binary>>, function_uses) ->
    Key;
extract_key(<<"intentlogic--", Key/binary>>, intent_logic) ->
    Key;
extract_key(<<"job--", Key/binary>>, job) ->
    Key;
extract_key(<<"pool--", Key/binary>>, pool) ->
    Key;
extract_key(<<"user--", Key/binary>>, user) ->
    Key;
extract_key(<<"whatis--", Key/binary>>, whatis) ->
    Key;
extract_key(<<"data--", Key/binary>>, data) ->
    Key;
extract_key(_, _) ->
    undefined.
