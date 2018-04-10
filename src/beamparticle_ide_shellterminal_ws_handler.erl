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
-module(beamparticle_ide_shellterminal_ws_handler).
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
-export([terminal_started/3]).

%% @doc Inform shell terminal process that the terminal process
%%      is now alive.
-spec terminal_started(pid(), integer(), pid()) -> ok.
terminal_started(ShellTerminalPid, Id, Pid) ->
  ShellTerminalPid ! {terminal, Id, Pid}.

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
                    [{terminals, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                 _ ->
                     JwtToken = string:trim(Token),
                     case beamparticle_auth:decode_jwt_token(JwtToken) of
                         {ok, Claims} ->
                             %% TODO validate jwt iss
                             #{<<"sub">> := Username} = Claims,
                             case beamparticle_auth:read_userinfo(Username, websocket, false) of
                                 {error, _} ->
                                     [{terminals, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                                 UserInfo ->
                                     [{terminals, []}, {calltrace, false}, {userinfo, UserInfo}, {dialogue, []} | State]
                             end;
                         _ ->
                            [{terminals, []}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State]
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
    lager:debug("init beamparticle_ide_shellterminal_ws_handler websocket"),
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
websocket_info({terminal, Id, Pid} = _Info, State) ->
    %% the terminal process is sending its websocket Pid now
    lager:debug("websocket info"),
    Terminals = proplists:get_value(terminals, State),
    case lists:keytake(Id, 1, Terminals) of
        {value, {Id, undefined}, Terminals2} ->
            erlang:link(Pid),
            lager:info("[~p] ~p linked successfully with terminal Id = ~p, Pid = ~p",
                       [self(), ?MODULE, Id, Pid]),
            beamparticle_ide_terminals_ws_handler:linked(Pid, Id, self()),
            NewEntry = {Id, Pid},
            State2 = proplists:delete(terminals, State),
            State3 = [{terminals, [NewEntry| Terminals2]} | State2],
            {ok, State3, hibernate};
        {value, {Id, OldPid}, _} ->
            %% TODO inform terminal back about this issue
            lager:error("[~p] ~p Pid = ~p already exists with terminal Id = ~p", [self(), ?MODULE, OldPid, Id]),
            {ok, State, hibernate};
        false ->
            %% TODO inform terminal back about this issue
            lager:error("[~p] ~p cannot find older terminal with Id = ~p", [self(), ?MODULE, Id]),
            {ok, State, hibernate}
    end;
%% send notification when a terminal terminates.
%% {"jsonrpc":"2.0","method":"onTerminalExitChanged","params":{"terminalId":26,"code":0,"signal":"1"}}
websocket_info({'EXIT', Pid, _} = Info, State) ->
    Terminals = proplists:get_value(terminals, State),
    case lists:keytake(Pid, 2, Terminals) of
        {value, {Id, Pid}, Terminals2} ->
            lager:info("[~p] ~p unlinked successfully with terminal Id = ~p, Pid = ~p upon Info = ~p",
                       [self(), ?MODULE, Id, Pid, Info]),
            %% TODO using hard-coded value for code and signal for now
            Code = 0,
            Signal = <<"1">>,
            JsonRpc = #{
              <<"jsonrpc">> => <<"2.0">>,
              <<"method">> => <<"onTerminalExitChanged">>,
              <<"params">> => #{<<"terminalId">> => Id,
                                <<"code">> => Code,
                                <<"signal">> => Signal}},
            Msg = jiffy:encode(JsonRpc),
            State2 = proplists:delete(terminals, State),
            State3 = [{terminals, Terminals2} | State2],

            %% cleanup terminal mapping at the end
            beamparticle_ide_terminals_server:delete(Id),
            {reply, {text, Msg}, State3, hibernate};
        false ->
            {ok, State, hibernate}
    end;
websocket_info(_Info, State) ->
    lager:debug("websocket info"),
    {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% When a new terminal is opened
%% {"jsonrpc":"2.0","id":0,"method":"create","params":{"rootURI":"file:///opt/beamparticle-data"}}
%% {"jsonrpc":"2.0","id":0,"result":26}
%%
%% When resizing existing terminal, where (TODO)
%% 1. first argument is the shell id allocated earlier
%% 2. second argument is number of columns
%% 3. third argument is number of rows
%%
%% {"jsonrpc":"2.0","id":1,"method":"resize","params":[26,67,13]}
%% {"jsonrpc":"2.0","id":1,"result":null}
%%
%% Notice the client will open another websocket just for interacting with
%% the terminal.
%%
%% The user sends close terminal here as well.
%% {"jsonrpc":"2.0","id":12,"method":"close","params":26}
%% Resp: {"jsonrpc":"2.0","id":12,"result":null}
%% Notification: {"jsonrpc":"2.0","method":"onTerminalExitChanged","params":{"terminalId":26,"code":0,"signal":"1"}}
run_query(#{<<"id">> := Id,
            <<"method">> := <<"create">>,
            <<"params">> := _Params} = _QueryJsonRpc,
          State) ->
    {ok, NextId} = beamparticle_ide_terminals_server:create(self()),
    Terminals = proplists:get_value(terminals, State),
    NewEntry = {NextId, undefined},
    State2 = proplists:delete(terminals, State),
    State3 = [{terminals, [NewEntry| Terminals]} | State2],
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => NextId},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State3, hibernate};
run_query(#{<<"id">> := Id} = _QueryJsonRpc, State) ->
    ResponseJsonRpc = #{
      <<"jsonrpc">> => <<"2.0">>,
      <<"id">> => Id,
      <<"result">> => null},
    Resp = jiffy:encode(ResponseJsonRpc),
    {reply, {text, Resp}, State, hibernate}.

