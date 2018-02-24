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
-module(beamparticle_nlp_ws_handler).
-author("neerajsharma").

%-behaviour(cowboy_http_handler).
%-behaviour(cowboy_websocket_handler).

-include("beamparticle_constants.hrl").

%% API

-export([init/2]).
-export([
  websocket_handle/2,
  websocket_info/2,
  websocket_init/1
]).

%% This is the default nlp-function
-define(DEFAULT_NLP_FUNCTION, <<"nlpfn">>).

%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    Opts = #{
        idle_timeout => 86400000},  %% 24 hours
    State2 = [{userinfo, undefined}, {dialogue, []} | State],
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
    erlang:put(?CALL_ENV_KEY, prod),
    lager:debug("init nlp websocket"),
    {ok, State}.

websocket_handle({text, Text}, State) ->
    beamparticle_ws_handler:run_query(fun handle_query/2, Text, State);
websocket_handle(Text, State) when is_binary(Text) ->
    %% sometimes the text is received directly as binary,
    %% so re-route it to core handler.
    websocket_handle({text, Text}, State);
websocket_handle(Any, State) ->
    AnyBin = list_to_binary(io_lib:format("~p", [Any])),
    Resp = <<"what did you mean by '", AnyBin/binary, "'?">>,
    Response = jsx:encode([{<<"text">>, Resp}, {<<"speak">>, Resp}]),
    {reply, {text, Response}, State, hibernate}.

websocket_info({timeout, _Ref, Msg}, State) ->
  {reply, {text, Msg}, State, hibernate};
websocket_info(_Info, State) ->
  lager:debug("websocket info"),
  {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

handle_query(Text, State) ->
    lager:info("NLP Query: ~s (~p)", [Text, Text]),
    FnName = ?DEFAULT_NLP_FUNCTION,
    SafeText = iolist_to_binary(string:replace(Text, <<"\"">>, <<>>, all)),
    NlpCall = <<FnName/binary, "(<<\"", SafeText/binary, "\">>)">>,
    FunctionBody = beamparticle_erlparser:create_anonymous_function(NlpCall),
    beamparticle_ws_handler:handle_run_command(FunctionBody, State).

