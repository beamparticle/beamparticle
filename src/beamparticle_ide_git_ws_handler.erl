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
-module(beamparticle_ide_git_ws_handler).
-author("neerajsharma").

-include("beamparticle_constants.hrl").

%% API

-export([init/2]).
-export([
  websocket_handle/2,
  websocket_info/2,
  websocket_init/1
]).

-export([run_query/2]).

%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    Opts = #{
      idle_timeout => 86400000},  %% 24 hours
    %% userinfo must be a map of user meta information
    lager:debug("beamparticle_ws_handler:init(~p, ~p)", [Req, State]),
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
    lager:debug("init beamparticle_ide_git_ws_handler websocket"),
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

websocket_info({timeout, _Ref, Msg}, State) ->
  {reply, {text, Msg}, State, hibernate};
websocket_info(_Info, State) ->
  lager:debug("websocket info"),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% {"jsonrpc":"2.0","id":0,"method":"repositories","params":["file:///opt/beamparticle-data",{"maxCount":1}]}
%% {"jsonrpc":"2.0","id":0,"result":[{"localUri":"file:///opt/beamparticle-data/git-data/git-src"}]}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"repositories">>,
            <<"params">> := _Params} = _QueryJsonRpc, State) ->
    %% TODO FIXME
    Result = #{
      <<"localUri">> => <<"file:///opt/beamparticle-data/git-data/git-src">>
     },
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
%%
%% {"jsonrpc":"2.0","id":3,"method":"status","params":{"localUri":"file:///opt/beamparticle-data/git-data/git-src"}}
%% {"jsonrpc":"2.0","id":3,"result":{"exists":true,"branch":"master","changes":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/nlpfn_top_page.erl.fun","status":2,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","status":2,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/.test.py.swp","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","status":0,"staged":false}],"currentHead":"cc295573f6eac81545d60e91794b66f1aaaa5c55"}}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"status">>,
            <<"params">> := _Params} = _QueryJsonRpc, State) ->
    %% TODO FIXME
    Result = #{
      <<"branch">> => <<"master">>,
      <<"changes">> => [],
      <<"currentHeader">> => <<"cc295573f6eac81545d60e91794b66f1aaaa5c55">>,
      <<"exists">> => true
     },
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
run_query(#{<<"id">> := Id,
            <<"method">> := <<"branch">>} = _QueryJsonRpc, State) ->
    %% TODO FIXME
    Result = [],
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
%%
%% $ git status
%% On branch master
%% Changes to be committed:
%%   (use "git reset HEAD <file>..." to unstage)
%% 
%%	modified:   nlpfn_top_page.erl.fun
%%	new file:   test3.erl.fun
%%	modified:   test_get.erl.fun
%%	new file:   test_java2.java.fun
%%	new file:   test_python_simple_http.py.fun
%%
%% Changes not staged for commit:
%%   (use "git add <file>..." to update what will be committed)
%%   (use "git checkout -- <file>..." to discard changes in working directory)
%%
%%	modified:   test.erl
%%
%% Untracked files:
%%  (use "git add <file>..." to include in what will be committed)
%%
%%	test.py
%%	test_conditions.erl.fun
%%
%%
%% $ git log
%% commit cc295573f6eac81545d60e91794b66f1aaaa5c55
%% Author: beamparticle <beamparticle@localhost>
%% Date:   Wed Apr 4 17:05:41 2018 +0530
%%
%%    test123
%%
%% $ git log -n1 --format="%H" -n 1
%% cc295573f6eac81545d60e91794b66f1aaaa5c55
%%
%%
%% see https://github.com/theia-ide/theia/packages/git/src/common/git-model.ts
%% GitFileStatus is an Enum
%% https://github.com/theia-ide/theia/blob/02cd33f3a8026744e6bd3596478f8f42eb5e5c6e/packages/git/src/common/git-model.ts
%%  'New',        0
%%  'Copied',     1
%%  'Modified',   2
%%  'Renamed',    3
%%  'Deleted',    4
%%  'Conflicted', 5
%%
%%
%% Refresh git status
%% {"jsonrpc":"2.0","id":13,"method":"status","params":{"localUri":"file:///opt/beamparticle-data/git-data/git-src"}}
%% {"jsonrpc":"2.0","id":13,"result":{"exists":true,"branch":"master","changes":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/nlpfn_top_page.erl.fun","status":2,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","status":2,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test3.erl.fun","status":0,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_get.erl.fun","status":2,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_java2.java.fun","status":0,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_python_simple_http.py.fun","status":0,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_conditions.erl.fun","status":0,"staged":false}],"currentHead":"cc295573f6eac81545d60e91794b66f1aaaa5c55"}}
%% Get git status for specific file
%% {"jsonrpc":"2.0","id":14,"method":"lsFiles","params":[{"localUri":"file:///opt/beamparticle-data/git-data/git-src"},"file:///opt/beamparticle-data/git-data/git-src/nlp.erl.fun",{"errorUnmatch":true}]}
%% {"jsonrpc":"2.0","id":14,"result":true}
%%
%%
%%
%% {"jsonrpc":"2.0","id":15,"method":"show","params":[{"localUri":"/opt/beamparticle-data/git-data/git-src"},"gitrev:/opt/beamparticle-data/git-data/git-src/nlp.erl.fun?HEAD",{"commitish":"HEAD"}]}
%% {"jsonrpc":"2.0","id":15,"result":"#!erlang\nfun(InputText) ->\n    Text = string:lowercase(InputText),\n    RequestJsonBin = jiffy:encode(#{<<\"message\">> => Text}),\n    IntentFunctions = [py_weather_intent_analysis, py_music_intent_analysis, py_greeting_intent_analysis],\n    Intents = lists:foldl(fun(Fn, AccIn) ->\n                                FnResult = Fn(RequestJsonBin, <<>>),\n                                lists:foldl(fun(E, AccIn2) ->\n                                                IntentType = maps:get(<<\"intent_type\">>, E),\n                                                AccIn2#{IntentType => E}\n                                            end, AccIn, jiffy:decode(FnResult, [return_maps]))\n                        end, #{}, IntentFunctions),\n    \n    \n    MostProbableIntentsResult = maps:fold(fun(K, V, AccIn) ->\n                                        {MaxConfidence, AccIntent} = AccIn,\n                                        Confidence = maps:get(<<\"confidence\">>, V),\n                                        case Confidence >= MaxConfidence of\n                                            true ->\n                                                {Confidence, AccIntent#{K => V}};\n                                            false ->\n                                                AccIn\n                                        end\n                            end, {0.0, #{}}, Intents),\n    % MostProbableIntents\n    % {proplists, [{speak, <<\"Hello Neeraj\">>}, {text, <<\"hello\">>}]}\n    {_, MostProbableIntents} = MostProbableIntentsResult,\n    InterestedIntents = iolist_to_binary(lists:join(<<\" and \">>, maps:keys(MostProbableIntents))),\n    SpeakMsg = case InterestedIntents of\n        <<>> ->\n            <<\"Hmm! I am sorry, but I don't know enough, to understand\">>;\n        _ ->\n            <<\"Looks like you are interested in \", InterestedIntents/binary>>\n    end,\n    {proplists, [{speak, SpeakMsg}, {text, SpeakMsg}]}\nend."}
%%
%%
%%
%% {"jsonrpc":"2.0","id":16,"method":"lsFiles","params":[{"localUri":"file:///opt/beamparticle-data/git-data/git-src"},"file:///opt/beamparticle-data/git-data/git-src/nlp.erl.fun",{"errorUnmatch":true}]}
%% {"jsonrpc":"2.0","id":16,"result":true}
%%
%%
%%
%% {"jsonrpc":"2.0","id":17,"method":"show","params":[{"localUri":"/opt/beamparticle-data/git-data/git-src"},"gitrev:/opt/beamparticle-data/git-data/git-src/nlp.erl.fun?HEAD",{"commitish":"HEAD"}]}
%% {"jsonrpc":"2.0","id":17,"result":"#!erlang\nfun(InputText) ->\n    Text = string:lowercase(InputText),\n    RequestJsonBin = jiffy:encode(#{<<\"message\">> => Text}),\n    IntentFunctions = [py_weather_intent_analysis, py_music_intent_analysis, py_greeting_intent_analysis],\n    Intents = lists:foldl(fun(Fn, AccIn) ->\n                                FnResult = Fn(RequestJsonBin, <<>>),\n                                lists:foldl(fun(E, AccIn2) ->\n                                                IntentType = maps:get(<<\"intent_type\">>, E),\n                                                AccIn2#{IntentType => E}\n                                            end, AccIn, jiffy:decode(FnResult, [return_maps]))\n                        end, #{}, IntentFunctions),\n    \n    \n    MostProbableIntentsResult = maps:fold(fun(K, V, AccIn) ->\n                                        {MaxConfidence, AccIntent} = AccIn,\n                                        Confidence = maps:get(<<\"confidence\">>, V),\n                                        case Confidence >= MaxConfidence of\n                                            true ->\n                                                {Confidence, AccIntent#{K => V}};\n                                            false ->\n                                                AccIn\n                                        end\n                            end, {0.0, #{}}, Intents),\n    % MostProbableIntents\n    % {proplists, [{speak, <<\"Hello Neeraj\">>}, {text, <<\"hello\">>}]}\n    {_, MostProbableIntents} = MostProbableIntentsResult,\n    InterestedIntents = iolist_to_binary(lists:join(<<\" and \">>, maps:keys(MostProbableIntents))),\n    SpeakMsg = case InterestedIntents of\n        <<>> ->\n            <<\"Hmm! I am sorry, but I don't know enough, to understand\">>;\n        _ ->\n            <<\"Looks like you are interested in \", InterestedIntents/binary>>\n    end,\n    {proplists, [{speak, SpeakMsg}, {text, SpeakMsg}]}\nend."}
%%
%%
%%
%%
%% {"jsonrpc":"2.0","id":18,"method":"show","params":[{"localUri":"/opt/beamparticle-data/git-data/git-src"},"gitrev:/opt/beamparticle-data/git-data/git-src/test_get.erl.fun?HEAD",{"commitish":"HEAD"}]}
%% {"jsonrpc":"2.0","id":18,"result":"fun(Body, Context) ->\n    log_info(\"An integer = ~p\", [10]),\n    log_error(\"Body=~p\", [Body]),\n    log_error(\"another one\"),\n    lists:foreach(fun(E) ->\n       log_error(\"a log entry ~p\", [E])\n       end, lists:seq(0, 10)),\n    Body\nend."}
%% ----
%% {"jsonrpc":"2.0","id":19,"method":"show","params":[{"localUri":"/opt/beamparticle-data/git-data/git-src"},"gitrev:/opt/beamparticle-data/git-data/git-src/test_get.erl.fun",{"commitish":""}]}
%% {"jsonrpc":"2.0","id":19,"result":"fun(Body, Context) ->\n    log_info(\"An integer = ~p\", [10]),\n    log_error(\"Body=~p\", [Body]),   \n    log_error(\"another one\"),\n    lists:foreach(fun(E) ->\n       log_error(\"a log entry ~p\", [E])\n       end, lists:seq(0, 10)),\n    Body\nend."}
run_query(#{<<"id">> := Id} = _QueryJsonRpc, State) ->
    %% TODO FIXME
    Result = null,
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => Result},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate}.

