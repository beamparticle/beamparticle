%%%-------------------------------------------------------------------
%%% @doc
%%% Handle zipkin client requests.
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
-module(beamparticle_zipkin_handler).

-export([init/2]).

-include("beamparticle_constants.hrl").
-include_lib("otter_lib/src/otter.hrl").


init(Req, Opts) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"POST">> ->
            HasBody = cowboy_req:has_body(Req),
            handle_client_request(Method, HasBody, Req, Opts);
        _ ->
            Req1 = cowboy_req:reply(?HTTP_METHOD_NOT_ALLOWED_CODE, Req),
            {halt, Req1, Opts}
    end.

%% no terminate required

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_client_request(_Method, true, Req, Opts) ->
    OpenTraceServerConfig = application:get_env(
        ?APPLICATION_NAME, opentracing_server, []),
    HttpMaxReadBytes = proplists:get_value(
        http_max_read_bytes, OpenTraceServerConfig, 1024 * 1024),
    HttpMaxReadTimeoutMsec = proplists:get_value(
        http_read_timeout_msec, OpenTraceServerConfig, 2000),
    Options = #{length => HttpMaxReadBytes, timeout => HttpMaxReadTimeoutMsec},
    case cowboy_req:read_body(Req, Options) of
        {ok, Body, Req1} ->
            Spans = otter_lib_zipkin_thrift:decode_spans(Body),
            lists:foreach(fun process_zipkin_span/1, Spans),
            Req2 = cowboy_req:reply(
                202,
                #{<<"X-Application-Context">> =>
                  <<"zipkin-server:shared:9411">>},
                <<>>,
                Req1
            ),
            {ok, Req2, Opts};
        _ ->
            %% timeout
            Req2 = cowboy_req:reply(
                           ?HTTP_REQUEST_TIMEOUT_CODE,
                           Req),
            {halt, Req2, Opts}
    end.

process_zipkin_span(Span) ->
    lager:debug("Span = ~p", [Span]),
    TimestampMicroSec = Span#span.timestamp,
    TraceId = Span#span.trace_id,
    Name = Span#span.name,
    Id = Span#span.id,
    ParentId = Span#span.parent_id,
    Tags = Span#span.tags,
    Logs = Span#span.logs,
    DurationMicroSeconds = Span#span.duration,

    Record = #{
      <<"timestamp_usec">> => TimestampMicroSec,
      <<"trace_id">> => TraceId,
      <<"name">> => Name,
      <<"id">> => Id,
      <<"parent_id">> => ParentId,
      <<"tags">> => Tags,
      <<"logs">> => Logs,
      <<"duration_usec">> => DurationMicroSeconds
     },
    lager:info("Record = ~p", [Record]),
    ok.

