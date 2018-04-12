%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% The protocol used is Language Server Protocol (LSP) as defined in
%%% version 2.0 of
%%% https://microsoft.github.io/language-server-protocol/specification
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
-module(beamparticle_ide_filesystem_ws_handler).
-author("neerajsharma").

-include("beamparticle_constants.hrl").

 -include_lib("kernel/include/file.hrl").

%% API

-export([init/2]).
-export([
  websocket_handle/2,
  websocket_info/2,
  websocket_init/1
]).

-export([run_query/2]).

-define(JSONRPC_URI, <<"uri">>).
-define(JSONRPC_IS_DIRECTORY, <<"isDirectory">>).
-define(JSONRPC_SIZE, <<"size">>).
-define(JSONRPC_CHILDREN, <<"children">>).
-define(JSONRPC_LAST_MODIFICATION, <<"lastModification">>).
-define(JSONRPC_RANGE, <<"range">>).
-define(JSONRPC_START, <<"start">>).
-define(JSONRPC_END, <<"end">>).
-define(JSONRPC_RANGE_LENGTH, <<"rangeLength">>).
-define(JSONRPC_LINE, <<"line">>).
-define(JSONRPC_CHARACTER, <<"character">>).
-define(JSONRPC_TEXT, <<"text">>).

-define(JSONRPC_VERSION, <<"2.0">>).

-define(LINE_TERMINATOR, <<"\n">>).


%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    Opts = #{
      idle_timeout => 86400000},  %% 24 hours
    %% userinfo must be a map of user meta information
    %% This is NOT the true process where websocket will run
    lager:info("[~p] beamparticle_ide_filesystem_ws_handler:init(~p, ~p)", [self(), Req, State]),
    Cookies = cowboy_req:parse_cookies(Req),
    Token = case lists:keyfind(<<"jwt">>, 1, Cookies) of
                {_, CookieJwtToken} -> CookieJwtToken;
                _ -> <<>>
            end,
    State2 = case Token of
                 <<>> ->
                    [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                 _ ->
                     JwtToken = string:trim(Token),
                     case beamparticle_auth:decode_jwt_token(JwtToken) of
                         {ok, Claims} ->
                             %% TODO validate jwt iss
                             #{<<"sub">> := Username} = Claims,
                             case beamparticle_auth:read_userinfo(Username, websocket, false) of
                                 {error, _} ->
                                     [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                                 UserInfo ->
                                     [{calltrace, false}, {userinfo, UserInfo}, {dialogue, []} | State]
                             end;
                         _ ->
                            [{calltrace, false}, {userinfo, undefined}, {dialogue, []} | State]
                     end
             end,
    {cowboy_websocket, Req, State2, Opts}.

%handle(Req, State) ->
%  lager:debug("Request not expected: ~p", [Req]),
%  {ok, Req2} = cowboy_http_req:reply(404, [{'Content-Type', <<"text/html">>}]),
%  {ok, Req2, State}.

%% In case you need to initialize use websocket_init/1 instead
%% of init/2.
websocket_init(State) ->
    %% Notice that init/2 is not called within the websocket actor,
    %% which websocket_init/1 is in the connected actor, so any
    %% changes to process dictionary here is correct.
    lager:info("[~p] beamparticle_ide_filesystem_ws_handler:websocket_init(~p)", [self(), State]),
    {ok, State}.

websocket_handle({text, Query}, State) ->
    case proplists:get_value(userinfo, State) of
        undefined ->
            %% do not reply unless authenticated
            {ok, State, hibernate};
        _UserInfo ->
            QueryJsonRpc = jiffy:decode(Query, [return_maps]),
            run_query(QueryJsonRpc, State)
    end;
websocket_handle(Text, State) when is_binary(Text) ->
    %% sometimes the text is received directly as binary,
    %% so re-route it to core handler.
    websocket_handle({text, Text}, State).

%% https://github.com/ninenines/cowboy/issues/165
websocket_info({timeout, _Ref, Msg}, State) ->
  {reply, {text, Msg}, State, hibernate};
websocket_info(hello, State) ->
  {reply, {text, <<"{}">>}, State, hibernate};
websocket_info(Info, State) ->
  lager:info("[~p] websocket info = ~p", [self(), Info]),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% When "enter" key is depressed at second line in the file test.erl. Note
%% that before changing the file, the file was 110 bytes long.
%%
%% {"jsonrpc":"2.0","id":15,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522894860563,"isDirectory":false,"size":110},[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"rangeLength":0,"text":"\n"}],null]}
%% {"jsonrpc":"2.0","id":15,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895615815,"isDirectory":false,"size":111}}
%%
%% Now when a character "a" was depressed then the following happens:
%% {"jsonrpc":"2.0","id":20,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895615815,"isDirectory":false,"size":111},[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"rangeLength":0,"text":"a"}],null]}
%% {"jsonrpc":"2.0","id":20,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895774115,"isDirectory":false,"size":112}}
%%
%% Now when the earlier character "a" is deleted
%% {"jsonrpc":"2.0","id":25,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895774115,"isDirectory":false,"size":112},[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"rangeLength":1,"text":""}],null]}
%% {"jsonrpc":"2.0","id":25,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895870256,"isDirectory":false,"size":111}}
%%
%% Now when two lines are added at beginning of the 3rd line in the file
%%
%% {"jsonrpc":"2.0","id":30,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522895870256,"isDirectory":false,"size":111},[{"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":0}},"rangeLength":0,"text":"new line 2\nnew line 3\n"}],null]}
%% {"jsonrpc":"2.0","id":30,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522896129472,"isDirectory":false,"size":133}}
%%
%% Notice that the start and end above indicates the area where the insert
%% occured, while the text indicates what needs to be inserted.
%%
%% Lets select the same text which was inserted earlier (notice the
%% new line at the end as well) and depress backspace key to delete.
%% Now we should be back to the original state of our file.
%% {"jsonrpc":"2.0","id":35,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522896129472,"isDirectory":false,"size":133},[{"range":{"start":{"line":2,"character":0},"end":{"line":4,"character":0}},"rangeLength":22,"text":""}],null]}
%% {"jsonrpc":"2.0","id":35,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522896356860,"isDirectory":false,"size":111}}
%%
%% Notice that the size is back to 111, additionally the range in request
%% clearly indicates that the replaced text is at line (2-1) first column
%% and ends at line (4-1) first column (inclusive). The replacement text
%% is empty as given in the text property.
%%
%%
%% Special cases of updates:
%% 1. use backspace at the start of a line, which should contents of line (11+1) with (11).
%% Note that we always add 1 because LSP uses zero index for line numbers and characters.
%% {"jsonrpc":"2.0","id":196,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522905388574,"isDirectory":false,"size":323},[{"range":{"start":{"line":11,"character":0},"end":{"line":12,"character":0}},"rangeLength":1,"text":""}],null]}
%%
%% 2. replace a block of multi-line text with a single char
%% {"jsonrpc":"2.0","id":236,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522909237900,"isDirectory":false,"size":322},[{"range":{"start":{"line":8,"character":3},"end":{"line":9,"character":8}},"rangeLength":30,"text":"a"}],null]}
%%
%% 3. 4 blank lines are deleted.
%% {"jsonrpc":"2.0","id":309,"method":"updateContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","lastModification":1522910286377,"isDirectory":false,"size":146},[{"range":{"start":{"line":6,"character":0},"end":{"line":10,"character":0}},"rangeLength":4,"text":""}],null]}
%%
run_query(#{<<"id">> := Id,
            <<"params">> := [FileInfo, UpdateInfos, null],
            <<"method">> := <<"updateContent">>} = _QueryJsonRpc,
          State) ->
    %%       When the user addeds information in between in an existing
    %%       file then it will send an updateContent method instead
    %%       of setContent.
    Uri = maps:get(?JSONRPC_URI, FileInfo),
    IsDir = maps:get(?JSONRPC_IS_DIRECTORY, FileInfo), %% TODO must be false
    false = IsDir,
    <<"file://", FilePath/binary>> = Uri,
    {ok, OldContent} = file:read_file(FilePath),
    %% OldContentBytes = byte_size(OldContent), %% TODO validate
    OldLines = string:split(OldContent, ?LINE_TERMINATOR, all), 
    %% [UpdateInfo] = UpdateInfos, %% TODO handle multiple updates at same time
    %% ---- cut
    NewOrderedLines = lists:foldl(fun(UpdateInfo, AccIn) ->
                                          lsp_update_old_content(UpdateInfo, AccIn)
                                  end, OldLines, UpdateInfos),
    Content = iolist_to_binary(lists:join(<<"\n">>, NewOrderedLines)),
    LastModificationEpochMsec = erlang:system_time(millisecond),
    ContentBytes = byte_size(Content),
    case file:write_file(FilePath, Content) of
        ok ->
            Result = #{
              ?JSONRPC_URI => Uri,
              ?JSONRPC_LAST_MODIFICATION => LastModificationEpochMsec,
              ?JSONRPC_IS_DIRECTORY => IsDir,
              ?JSONRPC_SIZE => ContentBytes},  %% Is size content size that we should be sending?
            ResponseJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"result">> => Result},
            Resp = jiffy:encode(ResponseJsonRpc),
            {reply, {text, Resp}, State, hibernate};
        _ ->
            %% https://github.com/theia-ide/theia/blob/bace685a8a77ad1ddfe986f1663cd7e081376c6b/packages/filesystem/src/node/node-filesystem.ts#L53
            ErrorRespJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"error">> => #{<<"code">> => -32603,
                               <<"message">> => iolist_to_binary(
                                                  [<<"Error occurred while writing file content. The file does not exist under ">>, Uri, <<".">>])}
             },
            ErrorResp = jiffy:encode(ErrorRespJsonRpc),
            {reply, {text, ErrorResp}, State, hibernate}
    end;
%% {"jsonrpc":"2.0","id":42,"method":"setContent","params":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","lastModification":1522853736983,"isDirectory":false,"size":87},"import sys\n\n\ndef main():\n    print(\"hello\")\n\ndef test1():\n    pass\n\n",null]}
%% {"jsonrpc":"2.0","id":42,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","lastModification":1522853828760,"isDirectory":false,"size":68}}
run_query(#{<<"id">> := Id,
            <<"params">> := [FileInfo, Content, null],
            <<"method">> := <<"setContent">>} = _QueryJsonRpc,
          State) ->
    %% NOTE: The client will send lesser bytes when the user is adding
    %%       content at the end of the file. This will ensure that
    %%       the client is appending information at the end.
    %%       When the user addeds information in between in an existing
    %%       file then it will send an updateContent method instead
    %%       of setContent.
    Uri = maps:get(?JSONRPC_URI, FileInfo),
    IsDir = maps:get(?JSONRPC_IS_DIRECTORY, FileInfo),
    ContentBytes = byte_size(Content),
    LastModificationEpochMsec = erlang:system_time(millisecond),
    <<"file://", FilePath/binary>> = Uri,
    case file:write_file(FilePath, Content) of
        ok ->
            Result = #{
              ?JSONRPC_URI => Uri,
              ?JSONRPC_LAST_MODIFICATION => LastModificationEpochMsec,
              ?JSONRPC_IS_DIRECTORY => IsDir,
              ?JSONRPC_SIZE => ContentBytes},  %% Is size content size that we should be sending?
            ResponseJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"result">> => Result},
            Resp = jiffy:encode(ResponseJsonRpc),
            {reply, {text, Resp}, State, hibernate};
        _ ->
            %% https://github.com/theia-ide/theia/blob/bace685a8a77ad1ddfe986f1663cd7e081376c6b/packages/filesystem/src/node/node-filesystem.ts#L53
            ErrorRespJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"error">> => #{<<"code">> => -32603,
                               <<"message">> => iolist_to_binary(
                                                  [<<"Error occurred while writing file content. The file does not exist under ">>, Uri, <<".">>])}
             },
            ErrorResp = jiffy:encode(ErrorRespJsonRpc),
            {reply, {text, ErrorResp}, State, hibernate}
    end;
%% {"jsonrpc":"2.0","id":15,"method":"resolveContent","params":["file:///opt/beamparticle-data/git-data/git-src/test.py",null]}
%% {"jsonrpc":"2.0","id":15,"result":{"stat":{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","lastModification":1522853599627,"isDirectory":false,"size":67},"content":"import sys\n\n\ndef main():\n    print(\"hello\")\n\ndef test1():\n    pass\n"}}
run_query(#{<<"id">> := Id,
            <<"params">> := [Uri, null],
            <<"method">> := <<"resolveContent">>} = _QueryJsonRpc,
          State) ->
    <<"file://", FilePath/binary>> = Uri,
    case file:read_file_info(FilePath, [{time, universal}]) of
        {ok, FileInfo} ->
            ContentBytes = FileInfo#file_info.size,
            IsDir = (FileInfo#file_info.type == directory),
            LastModificationEpochMsec = qdate:to_unixtime(FileInfo#file_info.mtime) * 1000,
            {ok, Content} = file:read_file(FilePath),
            Result = #{
              <<"stat">> => #{
                  ?JSONRPC_URI => Uri,
                  ?JSONRPC_LAST_MODIFICATION => LastModificationEpochMsec,
                  ?JSONRPC_IS_DIRECTORY => IsDir,
                  ?JSONRPC_SIZE => ContentBytes},
              <<"content">> => Content},
            ResponseJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"result">> => Result},
            Resp = jiffy:encode(ResponseJsonRpc),
            {reply, {text, Resp}, State, hibernate};
        _ ->
            ErrorRespJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"error">> => #{<<"code">> => -32603,
                               <<"message">> => iolist_to_binary(
                                                  [<<"Request resolveContent failed with message: Cannot find file under the given URI. URI: ">>, Uri, <<".">>])}
             },
            ErrorResp = jiffy:encode(ErrorRespJsonRpc),
            {reply, {text, ErrorResp}, State, hibernate}
    end;
run_query(#{<<"id">> := Id,
            <<"params">> := <<"file:///opt/beamparticle-data">>,
            <<"method">> := <<"getFileStat">>} = _QueryJsonRpc,
          State) ->
    Children = [#{?JSONRPC_URI => <<"file:///opt/beamparticle-data/git-data">>,
                  ?JSONRPC_LAST_MODIFICATION => 1522827712761,
                  ?JSONRPC_IS_DIRECTORY => true,
                  ?JSONRPC_CHILDREN => []}
                ,#{?JSONRPC_URI => <<"file:///opt/beamparticle-data/leveldb-k-data">>,
                   ?JSONRPC_LAST_MODIFICATION => 1522827712561,
                   ?JSONRPC_IS_DIRECTORY => true,
                   ?JSONRPC_CHILDREN => []}
                ,#{?JSONRPC_URI => <<"file:///opt/beamparticle-data/nlp">>,
                  ?JSONRPC_LAST_MODIFICATION => 1519132655597,
                  ?JSONRPC_IS_DIRECTORY => true,
                  ?JSONRPC_CHILDREN => []}
               ],
    Result = #{
      ?JSONRPC_URI => <<"file:///opt/beamparticle-data">>,
      ?JSONRPC_LAST_MODIFICATION => 1522841419376,
      ?JSONRPC_IS_DIRECTORY => true,
      ?JSONRPC_CHILDREN => Children},
    ResponseJsonRpc = #{
      <<"jsonrpc">> => ?JSONRPC_VERSION,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
run_query(#{<<"id">> := Id,
            <<"params">> := UriFolderPath,
            <<"method">> := <<"getFileStat">>} = _QueryJsonRpc,
          State) ->
    <<"file://", FolderPath/binary>> = UriFolderPath,
    {Files, IsDir, Found} = case filelib:is_dir(FolderPath) of
                                   true ->
                                       case file:list_dir(FolderPath) of
                                           {ok, L} ->
                                               {L, true, true}
                                       end;
                                   false ->
                                       case filelib:is_file(FolderPath) of
                                           true ->
                                               {[], false, true};
                                           false ->
                                               {[], false, false}
                                       end
                               end,
    case Found of
        true ->
            FolderPathStr = binary_to_list(FolderPath),
            Children = lists:foldl(fun(E, AccIn) ->
                                           P = FolderPathStr ++ "/" ++ E,
                                           {ok, EFileInfo} = file:read_file_info(P, [{time, universal}]),
                                           %%EIsDir = filelib:is_dir(P),
                                           %%LastModifiedMsec = qdate:to_unixtime(filelib:last_modified(P)) * 1000,
                                           EIsDir = (EFileInfo#file_info.type == directory),
                                           ELastModificationEpochMsec = qdate:to_unixtime(EFileInfo#file_info.mtime) * 1000,
                                           case EIsDir of
                                               true ->
                                                   [#{?JSONRPC_URI => iolist_to_binary([<<"file://">>, P]),
                                                      ?JSONRPC_LAST_MODIFICATION => ELastModificationEpochMsec,
                                                      ?JSONRPC_IS_DIRECTORY => EIsDir,
                                                      ?JSONRPC_CHILDREN => []} | AccIn];
                                               false ->
                                                   EContentBytes = EFileInfo#file_info.size,
                                                   [#{?JSONRPC_URI => iolist_to_binary([<<"file://">>, P]),
                                                      ?JSONRPC_LAST_MODIFICATION => ELastModificationEpochMsec,
                                                      ?JSONRPC_IS_DIRECTORY => EIsDir,
                                                      ?JSONRPC_SIZE => EContentBytes} | AccIn]
                                           end
                                   end, [], Files),
            Result = case IsDir of
                         true ->
                             #{
                              ?JSONRPC_URI => UriFolderPath,
                              ?JSONRPC_LAST_MODIFICATION => qdate:to_unixtime(filelib:last_modified(FolderPath)) * 1000,
                              ?JSONRPC_IS_DIRECTORY => IsDir,
                              ?JSONRPC_CHILDREN => Children};
                         false ->
                             {ok, FileInfo} = file:read_file_info(FolderPath, [{time, universal}]),
                             #{
                              ?JSONRPC_URI => UriFolderPath,
                              ?JSONRPC_LAST_MODIFICATION => qdate:to_unixtime(FileInfo#file_info.mtime) * 1000,
                              ?JSONRPC_IS_DIRECTORY => IsDir,
                              ?JSONRPC_SIZE => FileInfo#file_info.size}
                     end,
            ResponseJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"result">> => Result},
            Resp = jiffy:encode(ResponseJsonRpc),
            {reply, {text, Resp}, State, hibernate};
        false ->
            ErrorRespJsonRpc = #{
              <<"jsonrpc">> => ?JSONRPC_VERSION,
              <<"id">> => Id,
              <<"error">> => #{<<"code">> => -32603,
                               <<"message">> => iolist_to_binary(
                                                  [<<"Request getFileStat failed with message: Cannot find file under the given URI. URI: ">>, UriFolderPath, <<".">>])}
             },
            ErrorResp = jiffy:encode(ErrorRespJsonRpc),
            {reply, {text, ErrorResp}, State, hibernate}
    end;
run_query(#{<<"id">> := Id,
            <<"params">> := FilePath,
            <<"method">> := <<"exists">>} = _QueryJsonRpc,
          State) ->
    Result = case FilePath of
                 <<"file://", UnixFilePath/binary>> ->
                     filelib:is_file(UnixFilePath);
                 _ ->
                     false
             end,
    ResponseJsonRpc = #{
      <<"jsonrpc">> => ?JSONRPC_VERSION,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
run_query(#{<<"id">> := Id,
            <<"method">> := <<"getCurrentUserHome">>} = _QueryJsonRpc,
          State) ->
    run_query(#{<<"id">> => Id,
                <<"params">> => <<"file:///opt/beamparticle-data/git-data/git-src">>,
                <<"method">> => <<"getFileStat">>}, State);
%% {"jsonrpc":"2.0","id":16,"method":"createFile","params":"file:///opt/beamparticle-data/git-data/git-src/samplefile.py.fun"}
%% {"jsonrpc":"2.0","id":16,"result":{"uri":"file:///opt/beamparticle-data/git-data/git-src/samplefile.py.fun","lastModification":1522941368345,"isDirectory":false,"size":0}}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"createFile">>,
            <<"params">> := Uri} = _QueryJsonRpc,
          State) ->
    %% Create File
    Resp = case Uri of
                 <<"file://", OriginalFilePath/binary>> ->
                     FilePath = string:trim(OriginalFilePath),
                     case filelib:is_file(FilePath) of
                         true ->
                             ErrorRespJsonRpc2 = #{
                               <<"jsonrpc">> => ?JSONRPC_VERSION,
                               <<"id">> => Id,
                               <<"error">> => #{<<"code">> => -32603,
                                                <<"message">> => iolist_to_binary(
                                                                   [<<"Error occurred while writing file content. The file already exists under ">>, Uri, <<".">>])}
                              },
                             jiffy:encode(ErrorRespJsonRpc2);
                         false ->
                             NewFileContent = case classify_filepath(filename:basename(FilePath)) of
                                                  {ok, {_, 2, Lang}} ->
                                                      get_template_content(Lang);
                                                  {ok, {_, _Arity, _Lang}} ->
                                                      <<>>;
                                                  {error, _} = E ->
                                                      E
                                              end,
                             case NewFileContent of
                                 {error, ErrorMsg} ->
                                     ErrorRespJsonRpc = #{
                                       <<"jsonrpc">> => ?JSONRPC_VERSION,
                                       <<"id">> => Id,
                                       <<"error">> => #{<<"code">> => -32603,
                                                        <<"message">> => iolist_to_binary(
                                                                           [<<"Incorrect filename ">>, Uri, <<". ">>, ErrorMsg])}
                                      },
                                     jiffy:encode(ErrorRespJsonRpc);
                                 _ ->
                                     case file:write_file(FilePath, NewFileContent) of
                                         ok ->
                                             LastModificationEpochMsec = erlang:system_time(millisecond),
                                             Result = #{
                                              ?JSONRPC_URI => Uri,
                                              ?JSONRPC_LAST_MODIFICATION => LastModificationEpochMsec,
                                              ?JSONRPC_IS_DIRECTORY => false,
                                              ?JSONRPC_SIZE => 0},
                                             ResponseJsonRpc = #{
                                              <<"jsonrpc">> => ?JSONRPC_VERSION,
                                              <<"id">> => Id,
                                              <<"result">> => Result},
                                             jiffy:encode(ResponseJsonRpc);
                                         _ ->
                                             ErrorRespJsonRpc2 = #{
                                               <<"jsonrpc">> => ?JSONRPC_VERSION,
                                               <<"id">> => Id,
                                               <<"error">> => #{<<"code">> => -32603,
                                                                <<"message">> => iolist_to_binary(
                                                                                   [<<"Error occurred while writing file content. The file does not exist under ">>, Uri, <<".">>])}
                                              },
                                             jiffy:encode(ErrorRespJsonRpc2)
                                     end
                             end
                     end;
                 _ ->
                     jiffy:encode(#{
                         <<"jsonrpc">> => ?JSONRPC_VERSION,
                         <<"id">> => Id,
                         <<"result">> => null})
             end,
    {reply, {text, Resp}, State, hibernate};
%% {"jsonrpc":"2.0","id":13,"method":"delete","params":"file:///opt/beamparticle-data/git-data/git-src/test.erl"}
%% {"jsonrpc":"2.0","id":23,"result":[{"path":"/home/username/.local/share/Trash/files/8fcf806a-3d86-4929-8f7a-e74876a6062d","info":"/home/username/.local/share/Trash/info/8fcf806a-3d86-4929-8f7a-e74876a6062d.trashinfo"}]}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"delete">>,
            <<"params">> := Uri} = _QueryJsonRpc,
          State) ->
    %% TODO Move the file to Trash (see above example), for potential
    %% recovery later.
    <<"file://", FilePath/binary>> = Uri,
    Result = case file:delete(FilePath) of
                 ok ->
                     %% TODO move to trash and return path (see example above)
                     [];
                 _ ->
                     null
             end,
    ResponseJsonRpc = #{
      <<"jsonrpc">> => ?JSONRPC_VERSION,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
run_query(#{<<"id">> := Id} = _QueryJsonRpc, State) ->
    ResponseJsonRpc = #{
      <<"jsonrpc">> => ?JSONRPC_VERSION,
      <<"id">> => Id,
      <<"result">> => null},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate}.


%% must be used with lists:foldl/3 or lists:foldr/3
lsp_apply_update(E, {{StartLineNumber, StartCharacter} = A,
                     {EndLineNumber, EndCharacter} = B,
                     ReplacementText,
                     LineNum, NewList} = _AccIn)
  when LineNum == StartLineNumber andalso
       LineNum == EndLineNumber ->
    Part1 = string:slice(E, 0, StartCharacter),
    Part2 = string:slice(E, EndCharacter),
    PatchedLine = iolist_to_binary([Part1, ReplacementText, Part2]),
    %%UpdatedNewList = case PatchedLine of
    %%                     <<>> -> NewList;
    %%                     _ -> [PatchedLine | NewList]
    %%                 end,
    UpdatedNewList = [PatchedLine | NewList],
    {A, B, ReplacementText, LineNum + 1, UpdatedNewList};
lsp_apply_update(E, {{StartLineNumber, StartCharacter} = A,
                     {EndLineNumber, _EndCharacter} = B,
                     ReplacementText,
                     LineNum, NewList} = _AccIn)
  when LineNum == StartLineNumber andalso
       LineNum < EndLineNumber ->
    Part1 = string:slice(E, 0, StartCharacter),
    PatchedLine = iolist_to_binary([Part1, ReplacementText]),
    %%UpdatedNewList = case PatchedLine of
    %%                     <<>> -> NewList;
    %%                     _ -> [PatchedLine | NewList]
    %%                 end,
    UpdatedNewList = [PatchedLine | NewList],
    {A, B, ReplacementText, LineNum + 1, UpdatedNewList};
lsp_apply_update(_, {{StartLineNumber, _StartCharacter} = A,
                     {EndLineNumber, _EndCharacter} = B,
                     ReplacementText,
                     LineNum, NewList} = _AccIn)
  when LineNum > StartLineNumber andalso
       LineNum < EndLineNumber ->
    {A, B, ReplacementText, LineNum + 1, NewList};
lsp_apply_update(E, {{StartLineNumber, _StartCharacter} = A,
                     {EndLineNumber, EndCharacter} = B,
                     ReplacementText,
                     LineNum, NewList} = _AccIn)
  when LineNum > StartLineNumber andalso
       LineNum == EndLineNumber ->
    %% this is a multi-line replacement, so
    %% merge the head with this part
    [H | RestNewList] = NewList,
    Part1 = string:slice(E, EndCharacter),
    PatchedLine = iolist_to_binary([H | Part1]),
    %%UpdatedNewList = case PatchedLine of
    %%                     <<>> -> RestNewList;
    %%                     _ -> [PatchedLine | RestNewList]
    %%                 end,
    UpdatedNewList = [PatchedLine | RestNewList],
    {A, B, ReplacementText, LineNum + 1, UpdatedNewList};
lsp_apply_update(E, {{_, _} = A,
                     {_, _} = B,
                     ReplacementText,
                     LineNum, NewList} = _AccIn) ->
    {A, B, ReplacementText, LineNum + 1, [E | NewList]}.


%% function to handle multiple updates
%% [#{<<"range">> => #{<<"end">> => #{<<"character">> => 0,<<"line">> => 21},<<"start">> => #{<<"character">> => 0,<<"line">> => 21}},<<"rangeLength">> => 0,<<"text">> => <<"\n">>},#{<<"range">> => #{<<"end">> => #{<<"character">> => 0,<<"line">> => 22},<<"start">> => #{<<"character">> => 0,<<"line">> => 22}},<<"rangeLength">> => 0,<<"text">> => <<"a">>}]
lsp_update_old_content(UpdateInfo, OldLines) ->
    _RangeLength = maps:get(?JSONRPC_RANGE_LENGTH, UpdateInfo), %% TODO validate
    ReplacementText = maps:get(?JSONRPC_TEXT, UpdateInfo),
    RangeInfo = maps:get(?JSONRPC_RANGE, UpdateInfo),
    StartInfo = maps:get(?JSONRPC_START, RangeInfo),
    StartLineNumber = maps:get(?JSONRPC_LINE, StartInfo),
    StartCharacter = maps:get(?JSONRPC_CHARACTER, StartInfo),
    EndInfo = maps:get(?JSONRPC_END, RangeInfo),
    EndLineNumber = maps:get(?JSONRPC_LINE, EndInfo),
    EndCharacter = maps:get(?JSONRPC_CHARACTER, EndInfo),

    %% TODO assuming that the range is correct
    {_, _, _, _, NewLines} = lists:foldl(fun lsp_apply_update/2,
                                      {{StartLineNumber, StartCharacter},
                                       {EndLineNumber, EndCharacter},
                                       ReplacementText,
                                       0,
                                       []},
                                      OldLines),
    lists:reverse(NewLines).


classify_filepath(Filename) ->
    case string:split(Filename, <<"-">>) of
        [FunctionName, Rest] ->
            case string:split(Rest, <<".">>, all) of
                [Arity, ShortLang, <<"fun">>] when Arity >= 0 ->
                    try
                        {ok, {FunctionName,
                              binary_to_integer(Arity),
                              short_language_to_language(ShortLang)}}
                    catch
                        _:_ ->
                            {error, <<"Incorrect filename which must be <fname>-<arity>.<lang>.fun">>}
                    end;
                _ ->
                    {error, <<"Incorrect filename which must be <fname>-<arity>.<lang>.fun">>}
            end;
        _ ->
            {error, <<"Incorrect filename which must be <fname>-<arity>.<lang>.fun">>}
    end.

get_template_content(erlang) ->
    get_template_file_content("api_simple_erlang.2.erl.fun");
get_template_content(elixir) ->
    get_template_file_content("api_simple_elixir.2.ex.fun");
get_template_content(efene) ->
    get_template_file_content("api_simple_efene.2.efe.fun");
get_template_content(python) ->
    get_template_file_content("api_simple_python.2.py.fun");
get_template_content(java) ->
    get_template_file_content("api_simple_java.2.java.fun");
get_template_content(php) ->
    get_template_file_content("api_simple_php.2.php.fun").

get_template_file_content(Filename) when is_list(Filename) ->
    PrivDir = code:priv_dir(?APPLICATION_NAME),
    {ok, Content} = file:read_file(PrivDir ++ "/templates/" ++ Filename),
    Content.

short_language_to_language(<<"erl">>) -> erlang;
short_language_to_language(<<"ex">>) -> elixir;
short_language_to_language(<<"efe">>) -> efene;
short_language_to_language(<<"py">>) -> python;
short_language_to_language(<<"java">>) -> java;
short_language_to_language(<<"php">>) -> php.
