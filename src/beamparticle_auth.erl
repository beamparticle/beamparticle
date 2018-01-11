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

-include("beamparticle_constants.hrl").


%% @doc Get prefix used to store user auth
%% @private
-spec get_user_storage_prefix(websocket | http_rest) -> binary().
get_user_storage_prefix(websocket) ->
    <<"websocket-">>;
get_user_storage_prefix(http_rest) ->
    <<"http_rest-">>.

%% @doc Are there any users in datastore for auth
-spec any_user_exists(Prefix :: binary() | websocket | http_rest) -> boolean().
any_user_exists(websocket = Type) ->
    Prefix = get_user_storage_prefix(Type),
    any_user_exists(Prefix);
any_user_exists(http_rest = Type) ->
    Prefix = get_user_storage_prefix(Type),
    any_user_exists(Prefix);
any_user_exists(Prefix) when is_binary(Prefix) ->
    PrefixLen = byte_size(Prefix),
    Fn = fun({K, _V}, AccIn) ->
                 {R, S2} = AccIn,
                 case beamparticle_storage_util:extract_key(K, user) of
                     undefined ->
                         throw({{ok, R}, S2});
                     <<Prefix:PrefixLen/binary, _/binary>> = ExtractedKey ->
                         %% return as soon as we get one key which matches
                         throw({{ok, [ExtractedKey | R]}, S2});
                     _ ->
                         throw({{ok, R}, S2})
                 end
         end,
    {ok, Resp} = beamparticle_storage_util:lapply(Fn, Prefix, user),
	Resp =/= [].

%% TODO FIXME - keep user/password outside of beamparticle_storage_util for security
create_user(User, Password, Type) when Type == websocket orelse Type == http_rest ->
    HashedPassword = crypto:hash(sha, Password),
    Prefix = get_user_storage_prefix(Type),
    beamparticle_storage_util:write(
      <<Prefix/binary, User/binary>>, HashedPassword, user).

%% @todo separate authentication based on medium
%% (websocket or http_rest) and also on request path.
-spec authenticate_user(cowboy_req:req(), websocket | http_rest) ->
    {true | false, cowboy_req:req(), undefined | term()}.
authenticate_user(#{peer := {{127,0,0,1}, _}} = Req, _Type) ->
    %% allow access from localhost without any user
    %% authentication
    {true, Req, <<"localhost">>};
authenticate_user(Req, Type) when Type == websocket orelse Type == http_rest ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
		{basic, User, Password} ->
            Prefix = get_user_storage_prefix(Type),
            HashedPassword = crypto:hash(sha, Password),
            case any_user_exists(Type) of
                true ->
                    case beamparticle_storage_util:read(<<Prefix/binary, User/binary>>, user) of
                        {ok, HashedPassword} ->
                            {true, Req, User};
                        _ ->
                            {false, Req, undefined}
                    end;
                false ->
                    {ok, AuthConfig} = application:get_env(?APPLICATION_NAME, auth),
                    DefaultUser = proplists:get_value(default_user, AuthConfig),
                    DefaultPassword = proplists:get_value(default_password, AuthConfig),
                    DefaultHashedPassword = crypto:hash(sha, DefaultPassword),
                    case {User, HashedPassword} of
                        {DefaultUser, DefaultHashedPassword} ->
                            {true, Req, User};
                        _ ->
                            {false, Req, undefined}
                    end
            end;
		_ ->
			{false, Req, undefined}
	end.

