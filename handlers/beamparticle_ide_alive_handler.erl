%%%-------------------------------------------------------------------
%%% @doc
%%% Alive for IDE.
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

-module(beamparticle_ide_alive_handler).

-include("beamparticle_constants.hrl").

-export([init/2]).

init(Req0, Opts) ->
    lager:debug("beamparticle_ide_alive_handler received request = ~p, Opts = ~p", [Req0, Opts]),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json; charset=utf-8">>,
                                  <<"connection">> => <<"keep-alive">>}, <<>>, Req0),
    {ok, Req, Opts}.

