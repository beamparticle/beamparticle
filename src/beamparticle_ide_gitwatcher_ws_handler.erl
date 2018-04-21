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
-module(beamparticle_ide_gitwatcher_ws_handler).
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
                    [{watches, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                 _ ->
                     JwtToken = string:trim(Token),
                     case beamparticle_auth:decode_jwt_token(JwtToken) of
                         {ok, Claims} ->
                             %% TODO validate jwt iss
                             #{<<"sub">> := Username} = Claims,
                             case beamparticle_auth:read_userinfo(Username, websocket, false) of
                                 {error, _} ->
                                     [{watches, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                                 UserInfo ->
                                     [{watches, []}, {calltrace, false}, {userinfo, UserInfo}, {dialogue, []} | State]
                             end;
                         _ ->
                            [{watches, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State]
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
    lager:debug("init beamparticle_ide_gitwatcher_ws_handler websocket"),
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
websocket_info({change_event, Path} = Info, State) ->
    lager:debug("websocket received change event = ~p", [Info]),
    %% A sample event is as follows:
    %% {"jsonrpc":"2.0","method":"onGitChanged","params":{"source":{"localUri":"file:///opt/beamparticle-data/git-data/git-src"},"status":{"exists":true,"branch":"master","changes":[{"uri":"file:///opt/beamparticle-data/git-data/git-src/api_health-2.erl.fun","status":2,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res2","status":0,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.erl","status":2,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test2.erl.fun","status":4,"staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_stage_moved.erl.fun","status":3,"oldUri":"file:///opt/beamparticle-data/git-data/git-src/test_stage.erl.fun","staged":true},{"uri":"file:///opt/beamparticle-data/git-data/git-src/weather_for_city-2.erl.fun","status":2,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res10","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res3","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res4","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/res5.erl.fun","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test.py","status":0,"staged":false},{"uri":"file:///opt/beamparticle-data/git-data/git-src/test_conditions.erl.fun","status":0,"staged":false}],"currentHead":"9690596b0df0e22784a0ad9f3fa5693ceccc435e"}}}
    Uri = iolist_to_binary([<<"file://">>, Path]),
    UriStatus = beamparticle_ide_git_ws_handler:git_repo_detailed_changes(
                 Path, Uri),
    Params = #{
      <<"source">> => #{
          <<"localUri">> => Uri},
      <<"status">> => UriStatus},
    Event = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"method">> => <<"onGitChanged">>,
      <<"params">> => Params},
    Msg = jiffy:encode(Event),
    {reply, {text, Msg}, State, hibernate};
websocket_info(_Info, State) ->
  lager:debug("websocket info"),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% {"jsonrpc":"2.0","id":0,"method":"watchGitChanges","params":{"localUri":"file:///opt/beamparticle-data/git-data/git-src"}}
%% {"jsonrpc":"2.0","id":0,"result":1}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"watchGitChanges">>,
            <<"params">> := #{
               <<"localUri">> := <<"file:///opt/beamparticle-data/git-data/git-src">>}
           } = _QueryJsonRpc, State) ->
    FilePath = <<"/opt/beamparticle-data/git-data/git-src">>,
    Watches = proplists:get_value(watches, State),
    NextWatchInfo = case Watches of
                      [] -> {1, FilePath};
                      [{H, _} | _] ->
                          {H + 1, FilePath}
                  end,
    {NextWatchId, _} = NextWatchInfo,
    State2 = proplists:delete(watches, State),
    State3 = [{watches, [NextWatchInfo | Watches]} | State2],
    %% TODO: do not watch at present but send only once
    self() ! {change_event, FilePath},
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => NextWatchId},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State3, hibernate};
%% {"jsonrpc":"2.0","id":13,"method":"unwatchGitChanges","params":6}
%% {"jsonrpc":"2.0","id":13,"result":null}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"unwatchGitChanges">>,
            <<"params">> := WatchId} = _QueryJsonRpc,
          State) ->
    Watches = proplists:get_value(watches, State),
    State3 = case lists:keytake(WatchId, 1, Watches) of
        {value, {WatchId, _FilePath}, Watches2} ->
            State2 = proplists:delete(watches, State),
            [{watches, Watches2} | State2];
        false ->
            State
    end,
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => null},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State3, hibernate};
run_query(#{<<"id">> := Id} = _QueryJsonRpc, State) ->
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => null},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate}.

