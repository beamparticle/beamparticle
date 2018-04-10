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

-export([authenticate_user/2, authenticate_user/3, create_user/3]).
-export([hash_password_hmac/3]).
-export([userinfo/0]).
-export([create_jwt_auth_response/2, decode_jwt_token/1, read_userinfo/3]).

-include("beamparticle_constants.hrl").


%% @doc Retrieve logged-in user information from process dictionary
-spec userinfo() -> undefined | term().
userinfo() ->
    erlang:get(?USERINFO_ENV_KEY).

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
create_user(Username, Password, Type) when Type == websocket orelse Type == http_rest ->
	Salt = generate_salt(),
	{ok, PasswordHash} = hash_password(Password, Salt),
    Prefix = get_user_storage_prefix(Type),
    Key = <<Prefix/binary, Username/binary>>,
    JwtAuth = create_jwt_auth_response(Username, ?DEFAULT_JWT_EXPIRY_SECONDS),
    UserInfo = #{<<"username">> => Username,
                 <<"name">> => <<>>, %% TODO FIXME
                 <<"password_hash">> => beamparticle_util:bin_to_hex_binary(PasswordHash),
                 <<"password_salt">> => beamparticle_util:bin_to_hex_binary(Salt),
                 <<"hash_algo">> => <<"sha256">>,
                 <<"role">> => <<"general">>,
                 <<"scope">> => [],
                 <<"extra">> => #{},  %% extra information (custom), could be used by dynamic functions
                 <<"jwt">> => JwtAuth
                },
    Value = jiffy:encode(UserInfo),
    beamparticle_storage_util:write(Key, Value, user).

read_userinfo(Username, Type, MigrateIfRequired) when Type == websocket orelse
                                                      Type == http_rest ->
    case any_user_exists(Type) of
        true ->
            Prefix = get_user_storage_prefix(Type),
            Key = <<Prefix/binary, Username/binary>>,
            case beamparticle_storage_util:read(Key, user) of
                {ok, Value} ->
                    try
                        jiffy:decode(Value, [return_maps])
                    catch
                        _:_ ->
                            case MigrateIfRequired of
                                true ->
                                    Password = Value,
                                    true = create_user(Username, Password, Type),
                                    %% tail recusion, which is guaranteed to return
                                    %% since we no longer migrate if still not complete
                                    read_userinfo(Username, Type, false);
                                false ->
                                    {error, unknown}
                            end
                    end;
                _ ->
                    {error, not_found}
            end;
        false ->
            {ok, AuthConfig} = application:get_env(?APPLICATION_NAME, auth),
            DefaultUser = proplists:get_value(default_user, AuthConfig),
            DefaultPassword = proplists:get_value(default_password, AuthConfig),
            Salt = generate_salt(),
            {ok, PasswordHash} = hash_password(DefaultPassword, Salt),
            case Username of
                DefaultUser ->
                    JwtAuth = create_jwt_auth_response(Username,
                                                       ?DEFAULT_JWT_EXPIRY_SECONDS),
                    UserInfo = #{<<"username">> => Username,
                                 <<"name">> => <<>>,
                                 <<"password_hash">> => beamparticle_util:bin_to_hex_binary(PasswordHash),
                                 <<"password_salt">> => beamparticle_util:bin_to_hex_binary(Salt),
                                 <<"hash_algo">> => <<"sha256">>,
                                 <<"role">> => <<"admin">>,
                                 <<"scope">> => [<<"all">>],
                                 <<"extra">> => #{},
                                 <<"jwt">> => JwtAuth
                                },
                    UserInfo;
                _ ->
                    {error, not_found}
            end
    end.

%% @todo separate authentication based on medium
%% (websocket or http_rest) and also on request path.
-spec authenticate_user(cowboy_req:req(), websocket | http_rest) ->
    {true | false, cowboy_req:req(), undefined | term()}.
authenticate_user(#{peer := {{127,0,0,1}, _}} = Req, _Type) ->
    %% allow access from localhost without any user
    %% authentication
    UserInfo = #{<<"username">> => <<"localhost">>,
                 <<"name">> => <<>>,
                 <<"password_hash">> => <<>>,
                 <<"password_salt">> => <<>>,
                 <<"hash_algo">> => <<"sha256">>,
                 <<"role">> => <<"general">>,
                 <<"scope">> => [<<"all">>],
                 <<"extra">> => #{},  %% extra information (custom), could be used by dynamic functions
                 <<"jwt">> => #{}
                },
    {true, Req, UserInfo};
authenticate_user(Req, Type) when Type == websocket orelse Type == http_rest ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, Username, Password} ->
            {IsValid, UserInfo} = authenticate_user(Username, Password, Type),
            {IsValid, Req, UserInfo};

        %% see https://en.wikipedia.org/wiki/JSON_Web_Token
        %% http://self-issued.info/docs/draft-ietf-oauth-v2-bearer.html#authn-header
        {<<"bearer">>, Token} ->
            case decode_jwt_token(Token) of
                {ok, Claims} ->
                    %% TODO validate jwt iss
                    #{<<"sub">> := Username} = maps:from_list(Claims),
                    case read_userinfo(Username, Type, false) of
                        {error, _} ->
                            {false, Req, undefined};
                        UserInfo ->
                            {true, Req, UserInfo}
                    end;
                _ ->
                    {false, Req, undefined}
            end;
        _ ->
            {false, Req, undefined}
    end.

authenticate_user(Username, Password, Type) when Type == websocket orelse
                                                 Type == http_rest ->
    case any_user_exists(Type) of
        true ->
            case read_userinfo(Username, Type, true) of
                {error, _} ->
                    {false, undefined};
                UserInfo ->
                    Salt = beamparticle_util:hex_binary_to_bin(
                             maps:get(<<"password_salt">>, UserInfo)),
                    {ok, PasswordHash} = hash_password(Password, Salt),
                    StoredPasswordHashBin = beamparticle_util:hex_binary_to_bin(
                                              maps:get(<<"password_hash">>,
                                                       UserInfo)),
                    case StoredPasswordHashBin of
                        PasswordHash ->
                            {true, UserInfo};
                        _ ->
                            {false, undefined}
                    end
            end;
        false ->
            {ok, AuthConfig} = application:get_env(?APPLICATION_NAME, auth),
            DefaultUser = proplists:get_value(default_user, AuthConfig),
            DefaultPassword = proplists:get_value(default_password, AuthConfig),
            Salt = generate_salt(),
            {ok, DefaultPasswordHash} = hash_password(DefaultPassword, Salt),
            {ok, PasswordHash} = hash_password(Password, Salt),
            case {Username, PasswordHash} of
                {DefaultUser, DefaultPasswordHash} ->
                    JwtAuth = create_jwt_auth_response(Username,
                                                       ?DEFAULT_JWT_EXPIRY_SECONDS),
                    UserInfo = #{<<"username">> => Username,
                                 <<"name">> => <<>>,
                                 <<"password_hash">> => beamparticle_util:bin_to_hex_binary(PasswordHash),
                                 <<"password_salt">> => beamparticle_util:bin_to_hex_binary(Salt),
                                 <<"hash_algo">> => <<"sha256">>,
                                 <<"role">> => <<"admin">>,
                                 <<"scope">> => [<<"all">>],
                                 <<"extra">> => #{},
                                 <<"jwt">> => JwtAuth
                                },
                    {true, UserInfo};
                _ ->
                    {false, undefined}
            end
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

create_jwt_auth_response(Username, ExpirySeconds) ->
    JwtSub = Username,
    Claims = [{<<"sub">>, JwtSub}, {<<"iss">>, ?DEFAULT_JWT_ISS}],
    {ok, Token} = jwt:encode(?DEFAULT_JWT_ALGORITHM,
                             Claims,
                             ExpirySeconds,
                             ?DEFAULT_JWT_KEY),
    %% AuthResponse
    #{<<"access_token">> => Token,
      <<"token_type">> => <<"JWT">>,
      <<"issuer">> => ?DEFAULT_JWT_ISS,
      <<"expires_in">> => integer_to_binary(ExpirySeconds)}.

decode_jwt_token(Token) ->
    case jwt:decode(Token, ?DEFAULT_JWT_KEY) of
        {ok, Claims} ->
            %% #{<<"sub">> := JwtSub, <<"iss">> := JwtIss} = maps:from_list(Claims),
            {ok, Claims};
        _ ->
            {error, invalid}
    end.

%% @private
create_salt_uniform(N) ->
    <<<<(rand:uniform(255))>> || _X <- lists:seq(1, N)>>.

% SHA-256 requires 32 bytes
generate_salt() ->
    case create_salt(32) of
       {ok, {strong, Salt}} ->
           Salt;
       {ok, {uniform, Salt}} ->
           % TODO raise alarm
           Salt
    end.

%% @doc
%% Create salt of N bytes, which tries to generate strong random bytes
%% for cryptography, but when the entropy is not good enough this
%% function falls back on creating uniform random number (which is
%% less secure).
-spec create_salt(N :: integer()) ->
    {ok, {strong, binary()}} |
    {ok, {uniform, binary()}}.
create_salt(N) ->
    %% fallback to uniform random number when entropy is not good enough
    %% although that is not a very good idea
    try
        {ok, {strong, crypto:strong_rand_bytes(N)}}
    catch
        _ -> {ok, {uniform, create_salt_uniform(N)}}
    end.

%% @doc
%% Hash password via pbkdf2, with 128 iterations and SHA-256.
%% For less secure but faster version @see hash_password_hmac/3
-spec hash_password(binary(), binary()) -> {ok, binary()}.
hash_password(Password, Salt) ->
    Iterations = 128,
    DerivedLength = 32, % for SHA256
    {ok, _PasswordHash} =
    pbkdf2:pbkdf2(sha256, Password, Salt, Iterations, DerivedLength).

%% @doc
%% Hash password via SHA-1 HMAC, which is very fast but less secure.
%% There are better ways of hashing password, one of them being
%% using the erlang-pbkdf2, erlang-bcrypt or erl-scrypt project.
%%
%% For more secure version @see oms_util:hash_password/2
-spec hash_password_hmac(Key :: binary(), Password :: binary(),
                         Salt :: binary()) ->
                            {ok, binary()}.
hash_password_hmac(Key, Password, Salt) ->
    {ok, crypto:hmac(sha, Key, <<Password/binary, Salt/binary>>)}.

