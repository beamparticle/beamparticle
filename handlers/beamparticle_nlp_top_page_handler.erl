%%%-------------------------------------------------------------------
%%% @doc
%%% A handler to serve dynamic landing page for nlp
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

-module(beamparticle_nlp_top_page_handler).

-include("beamparticle_constants.hrl").

-export([init/2]).

init(Req0, Opts) ->
    #{env := Env} = cowboy_req:match_qs([{env, [], <<"1">>}], Req0),
    case Env of
        <<"2">> ->
            erlang:put(?CALL_ENV_KEY, stage);
        _ ->
            erlang:put(?CALL_ENV_KEY, prod)
    end,
    case beamparticle_dynamic:execute({<<"nlpfn_top_page">>, [Req0, Opts]}) of
        {ok, {Body, RespHeaders}} when (is_list(Body) orelse
                                        is_binary(Body)) andalso
                                       is_map(RespHeaders) ->
            Req = cowboy_req:reply(200, RespHeaders, Body, Req0),
            lager:info("Req = ~p, Body = ~p", [Req, Body]),
            erlang:erase(?CALL_ENV_KEY),
            {ok, Req, Opts};
		_ ->
			PrivDir = code:priv_dir(?APPLICATION_NAME),
			File = PrivDir ++ "/index-nlp.html",
			Size = filelib:file_size(File),
            lager:info("static file = ~p, size = ~p", [File, Size]),
			Req = cowboy_req:reply(200, #{}, {sendfile, 0, Size, File}, Req0),
            erlang:erase(?CALL_ENV_KEY),
            {ok, Req, Opts}
	end.
