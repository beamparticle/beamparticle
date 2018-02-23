%%%-------------------------------------------------------------------
%%% @doc
%%% A CRUD handler based on cowboy's rest framework.
%%% @end
%%%
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
%%%
%%%-------------------------------------------------------------------

-module(beamparticle_generic_handler).

-include("beamparticle_constants.hrl").

%% cowboy_rest callbacks
-export([init/2]).
-export([service_available/2]).
-export([allowed_methods/2]).
-export([is_authorized/2]).
-export([content_types_provided/2]).
-export([content_types_accepted/2]).
-export([resource_exists/2]).
-export([delete_resource/2]).

%% to avoid compiler error for unsed functions
-export([to_json/2, from_json/2]).


-record(state, {model :: module(),
                start = erlang:monotonic_time(milli_seconds),
                model_state :: term(),
                resource_id :: binary() | undefined,
                resource :: binary() | undefined}).

-define(MIMETYPE, {<<"application">>, <<"json">>, []}).
-define(MIMETYPE_DOC, "application/json").

%% @private called when starting the handling of a request
init(Req, _Opts=[Model]) ->
    Id = cowboy_req:binding(id, Req),
    QsProplist = cowboy_req:parse_qs(Req),
    State = #state{resource_id=Id, model=Model, model_state=Model:init(Id, QsProplist)},
	%% lager:info("State = ~p", [State]),
    %%{upgrade, protocol, cowboy_rest, Req, State}.
    Req2 = Req#{log_enabled => true},
    Req3 = Req2#{start_time => State#state.start},
    Req4 = Req3#{metrics_source => State#state.model},
    {cowboy_rest, Req4, State}.

%% @private Check if we're configured to be in lockdown mode to see if the
%% service should be available
service_available(Req, State) ->
    {not application:get_env(?APPLICATION_NAME, lockdown, false), Req, State}.

%% @private Allow CRUD stuff standard
allowed_methods(Req, State) ->
    {[<<"POST">>,<<"GET">>,<<"PUT">>,<<"DELETE">>], Req, State}.

%% @private No authorization in place for this demo, but this is it where it goes
%% TODO
is_authorized(Req, State) ->
    case beamparticle_auth:authenticate_user(Req, http_rest) of
        {true, _, UserInfo} ->
            %% save user information in process dictionary for
            %% any further use by model or dynamic functions
            erlang:put(?USERINFO_ENV_KEY, UserInfo),
            {true, Req, State};
        _ ->
            {{false, <<"basic realm=\"beamparticle\"">>}, Req, State}
    end.

%% @private Does the resource exist at all?
resource_exists(Req, State=#state{model=M, model_state=S}) ->
    %% @todo binding is already discovered in init
    case cowboy_req:binding(id, Req) of
        undefined ->
            {false, Req, State};
        Id ->
            Method = cowboy_req:method(Req),
            case Method of
                %% optimization: do not read when asked to write/overwrite
                <<"POST">> ->
                    {false, Req, State};
                <<"PUT">> ->
                    {false, Req, State};
                _ ->
                    case M:read(Id, S) of
                        { {ok, Resource}, NewS} ->
                            {true, Req, State#state{resource_id=Id, model_state=NewS, resource=Resource}};
                        { {error, not_found}, NewS} ->
                            {false, Req, State#state{resource_id=Id, model_state=NewS}}
                    end
            end
    end.

%%%===================================================================
%%% GET Callbacks
%%%===================================================================

%% @private
content_types_provided(Req, State) ->
    {[{?MIMETYPE, to_json}], Req, State}.

%% @private
to_json(Req, State=#state{resource=Resource}) when is_binary(Resource) ->
    {Resource, Req, State}.

%%%===================================================================
%%% DELETE Callbacks
%%%===================================================================

%% @private
delete_resource(Req, State=#state{resource_id=Id, model=M, model_state=S}) ->
    case M:delete(Id, S) of
        {true, NewS} -> {true, Req, State#state{model_state=NewS}};
        {_, NewS} -> {false, Req, State#state{model_state=NewS}}
    end.

%%%===================================================================
%%% PUT/POST Callbacks
%%%===================================================================

%% @private Define content types we accept and handle
content_types_accepted(Req, State) ->
    {[{?MIMETYPE, from_json}], Req, State}.

%% @private Handle the update and figure things out.
from_json(Req, State=#state{resource_id=Id, resource=R, model=M, model_state=S}) ->
    %% see https://ninenines.eu/docs/en/cowboy/2.0/guide/req_body/
    %%{Length, Req0} = cowboy_req:body_length(Req),
    %% {read_length, 12 * 1020 * 1024}, could use this setting as well
    %% read_timeout is in milliseconds
    {HttpMaxReadBytes, HttpMaxReadTimeoutMsec} =
        case application:get_env(?APPLICATION_NAME, http_rest) of
            {ok, HttpRestConfig} ->
                A = proplists:get_value(max_read_length,
                    HttpRestConfig, ?DEFAULT_MAX_HTTP_READ_BYTES),
                B = proplists:get_value(max_read_timeout_msec,
                    HttpRestConfig, ?DEFAULT_MAX_HTTP_READ_TIMEOUT_MSEC),
                {A, B};
            _ -> {?DEFAULT_MAX_HTTP_READ_BYTES,
                ?DEFAULT_MAX_HTTP_READ_TIMEOUT_MSEC}
        end,
    Options = #{length => HttpMaxReadBytes, timeout => HttpMaxReadTimeoutMsec},
    case cowboy_req:read_body(Req, Options) of
        {ok, Body, Req1} ->
            %%{ok, BodyIoList, Req1} = read_complete_payload(Req, []),
            Method = cowboy_req:method(Req1),
            %% TODO @todo already in init
            QsProplist = cowboy_req:parse_qs(Req1),
			lager:debug("Method = ~p, QsProplist = ~p, Body=~p", [Method, QsProplist, Body]),
            case Method of
                <<"PUT">> when Id =:= undefined; R =:= undefined ->
                    {false, Req1, State};
                _ ->
                    try
                        case {Method, M:validate(Body, S)} of
                            {<<"POST">>, {true, S2}} when Id =:= undefined andalso R =:= undefined ->
                                %% due to optimization, when repeated POST or PUT is used
                                %% for an existing Id, the guard above refer to Id not being
                                %% undefined. So, when Id is known then use M:update/4 and
                                %% unconditionally overwrite key value.
								lager:debug("~p:create(~p, ~p, ~p, ~p)", [M, Id, Body, QsProplist, S2]),
                                {Res, S3} = M:create(Id, Body, S2),
                                {NewRes, Req2} = post_maybe_expand(Res, Req1),
								lager:debug("Result = ~p", [{NewRes, Req2}]),
                                {NewRes, Req2, State#state{model_state=S3}};
                            {Method, {true, S2}} when
                                Method =:= <<"POST">> orelse Method =:= <<"PUT">> ->
								lager:debug("~p:update(~p, ~p, ~p, ~p)", [M, Id, Body, QsProplist, S2]),
                                {Res, S3} = M:update(Id, Body, S2),
                                {NewRes, Req2} = post_maybe_expand(Res, Req1),
                                {NewRes, Req2, State#state{model_state=S3}};
                            {_, {false, S2}} ->
                                {false, Req1, State#state{model_state=S2}}
                        end
                    catch
                        error:badarg ->
                            {false, Req1, State}
                    end
            end;
        _ ->
            %% timeout
            Req2 = cowboy_req:reply(
                           ?HTTP_REQUEST_TIMEOUT_CODE,
                           [{<<"content-type">>, <<"application/json">>}],
                           <<"{\"error\": 408, \"msg\": \"timeout\"}">>,
                           Req),
            {halt, Req2, State}
    end.

%% @private if the resource returned a brand new ID, set the value properly
%% for the location header.
post_maybe_expand({true, Id}, Req) ->
    Path = cowboy_req:path(Req),
    {{true, [Path, trail_slash(Path), Id]}, Req};
post_maybe_expand(Val, Req) when is_binary(Val) ->
    Req1 = cowboy_req:set_resp_header(<<"content-type">>,<<"application/json">>,Req),
    Req2 = cowboy_req:set_resp_body(Val, Req1),
	{true, Req2};
post_maybe_expand(Val, Req) ->
    {Val, Req}.

trail_slash(Path) ->
    case binary:last(Path) of
        $/ -> "";
        _ -> "/"
    end.


%%read_complete_payload(Req, AccIn) ->
%%    case cowboy_req:body(Req) of
%%        {more, PartialBody, Req1} -> read_complete_payload(Req1, [PartialBody | AccIn]);
%%        {ok, Body, Req1} -> {ok, lists:reverse([Body | AccIn]), Req1};
%%        {error, closed} -> lager:error("Peer closed cxn"), {error, closed};
%%        {error, timeout} -> lager:error("Peer timedout"), {error, timeout}
%%    end.
