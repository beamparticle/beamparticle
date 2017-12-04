%%%-------------------------------------------------------------------
%%% @doc
%%% Various utility functions to wrap common logging
%%% operations outside of what lager or error_logger support
%%% by default.
%%% @end
%%% Copyright (c) 2016, Fred Hebert <mononcqc@ferd.ca>.
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are
%%% met:
%%%
%%% * Redistributions of source code must retain the above copyright
%%%   notice, this list of conditions and the following disclaimer.
%%%
%%% * Redistributions in binary form must reproduce the above copyright
%%%   notice, this list of conditions and the following disclaimer in the
%%%   documentation and/or other materials provided with the distribution.
%%%
%%% * The names of its contributors may not be used to endorse or promote
%%%   products derived from this software without specific prior written
%%%   permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%%% A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%%% OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
%%% LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
%%% DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
%%% THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%%-------------------------------------------------------------------

-module(log_utils).
-export([req_log/4]).

%% @doc Request logs provided as a cowboy hook.
%%
%% Folsom metrics can be triggered by having the cowboy handler setting
%% a given `metrics_source' in the `meta' values of the `cowboy_req'
%% object. Counts for status codes returned will be accumulated.
%% If adding a `meta' value named `start_time', whose value is obtained
%% by calling `erlang:montonic_time(milli_seconds)',  time difference
%% calculation will be done between this time value and the end of the
%% response.
%%
%% By setting `log_enabled' to `true' in the `cowboy_req' `meta' object,
%% log lines for an HTTP status will be generated for each response.
req_log(Status, _Headers, _IoData, Req) ->
    Req1 = publish_metrics(Status, Req),
    Req2 = publish_req_logs(Status, Req1),
    Req2.

publish_metrics(Status, Req1) ->
    Type = if Status < 200 -> <<"1xx">>;
              Status < 300 -> <<"2xx">>;
              Status < 400 -> <<"3xx">>;
              Status < 500 -> <<"4xx">>;
              Status < 600 -> <<"5xx">>;
              true -> <<"bad_status">>
           end,
    publish_counter(Type, 1),
    case maps:get(metrics_source, Req1, undefined) of
        undefined ->
            Req1;
        Term when is_atom(Term) ->
            RootKey = atom_to_binary(Term, utf8),
            publish_counter(<<RootKey/binary,".",Type/binary>>, 1),
            case maps:get(start_time, Req1, undefined) of
                undefined ->
                    Req1;
                T0 ->
                    T1 = erlang:monotonic_time(milli_seconds),
                    publish_histogram(<<RootKey/binary,".",Type/binary,".ms"/utf8>>,
                                      T1-T0),
                    publish_histogram(<<RootKey/binary,".ms"/utf8>>, T1-T0),
                    Req1
            end
    end.

publish_req_logs(Status, Req1) ->
    case maps:get(log_enabled, Req1, false) of
        true ->
            Method = cowboy_req:method(Req1),
            {Path, Req4} = cowboy_req:path(Req1),
            {Agent, Req5} = cowboy_req:header(<<"user-agent">>, Req4, <<"">>),
            {{IP,_Port}, Req6} = cowboy_req:peer(Req5),
            Str = "method=~s path=~s status=~p ip=~s agent=~p",
            Args = [Method, Path, Status, format_ip(IP),
                    binary_to_list(Agent)],
            if Status < 500 -> req_logs:info(Str, Args);
               Status >= 500 -> req_logs:warning(Str, Args)
            end,
            Req6;
        false ->
            Req1
    end.

publish_counter(Key, Val) ->
    case folsom_metrics:notify({Key, {inc,Val}}) of
        {error, _, nonexistent_metric} ->
            folsom_metrics:new_counter(Key),
            folsom_metrics:notify({Key, {inc,Val}});
        ok ->
            ok
    end.

publish_histogram(Key, Val) ->
    case folsom_metrics:notify({Key, Val}) of
        {error, _, nonexistent_metric} ->
            folsom_metrics:new_histogram(Key),
            folsom_metrics:notify({Key, Val});
        ok ->
            ok
    end.

format_ip({A,B,C,D}) ->
    [integer_to_list(A), ".", integer_to_list(B), ".",
     integer_to_list(C), ".", integer_to_list(D)].

