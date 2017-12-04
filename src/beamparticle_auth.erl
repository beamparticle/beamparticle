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
-module(beamparticle_auth).

-export([authenticate_user/2, create_user/3]).


%% TODO FIXME - keep user/password outside of beamparticle_storage_util for security
create_user(User, Password, websocket) ->
    HashedPassword = crypto:hash(sha, Password),
    beamparticle_storage_util:write(<<"websocket-", User/binary>>, HashedPassword, user);
create_user(User, Password, http_rest) ->
    HashedPassword = crypto:hash(sha, Password),
    beamparticle_storage_util:write(<<"http_rest-", User/binary>>, HashedPassword, user).

%% @todo separate authentication based on medium
%% (websocket or http_rest) and also on request path.
-spec authenticate_user(cowboy_req:req(), websocket | http_rest) ->
    {true | false, cowboy_req:req(), undefined | term()}.
authenticate_user(Req, websocket) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
		{basic, User, Password} ->
            HashedPassword = crypto:hash(sha, Password),
            case beamparticle_storage_util:read(<<"websocket-", User/binary>>, user) of
                {ok, HashedPassword} ->
                    {true, Req, User};
                _ ->
                    {false, Req, undefined}
            end;
		_ ->
			{false, Req, undefined}
	end;
authenticate_user(Req, http_rest) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
		{basic, User, Password} ->
            HashedPassword = crypto:hash(sha, Password),
            case beamparticle_storage_util:read(<<"http_rest-", User/binary>>, user) of
                {ok, HashedPassword} ->
                    {true, Req, User};
                _ ->
                    {false, Req, undefined}
            end;
		_ ->
			{false, Req, undefined}
	end.
