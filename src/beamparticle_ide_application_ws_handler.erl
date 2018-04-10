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
-module(beamparticle_ide_application_ws_handler).
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
    lager:debug("init beamparticle_ide_application_ws_handler websocket"),
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

%% {"jsonrpc":"2.0","id":0,"method":"getApplicationInfo","params":null}
%% {"jsonrpc":"2.0","id":0,"result":{"name":"@theia/example-browser","version":"0.3.8"}}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"getApplicationInfo">>,
            <<"params">> := null} = _QueryJsonRpc, State) ->
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => #{<<"name">> => <<"beamparticle">>,
                        <<"version">> => <<"0.1.3">>}},  %% TODO derive this
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate};
%% {"jsonrpc":"2.0","id":1,"method":"getExtensionsInfos","params":null}
%% {"jsonrpc":"2.0","id":1,"result":[{"name":"@theia/core","version":"0.3.8"},{"name":"@theia/output","version":"0.3.8"}, ...]}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"getExtensionsInfos">>,
            <<"params">> := null} = _QueryJsonRpc, State) ->
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => []},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate}.
