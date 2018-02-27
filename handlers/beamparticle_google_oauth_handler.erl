%%%-------------------------------------------------------------------
%%% @doc
%%% Google OAuth Handler for both redirecting to Google for OAuth
%%% and handle Callback for authenticated users
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

-module(beamparticle_google_oauth_handler).

-include("beamparticle_constants.hrl").

-export([init/2]).

init(Req0, Opts) ->
    #{env := Env} = cowboy_req:match_qs([{env, [], <<"1">>}], Req0),
    lager:debug("beamparticle_google_oauth_handler received request = ~p, Opts = ~p", [Req0, Opts]),
    case Env of
        <<"2">> ->
            erlang:put(?CALL_ENV_KEY, stage);
        _ ->
            erlang:put(?CALL_ENV_KEY, prod)
    end,
    <<"/auth/", RestPath/binary>> = cowboy_req:path(Req0),
    GoogleOauthConfig = application:get_env(?APPLICATION_NAME, google_oauth, []),
    SocNets = simple_oauth2:customize_networks(simple_oauth2:predefined_networks(),
                                               [
                                                {<<"google">>, GoogleOauthConfig}
                                               ]),
    Scheme = cowboy_req:scheme(Req0),
    Host = cowboy_req:host(Req0),
    UrlPrefix = iolist_to_binary([Scheme, <<"://">>, Host]),
    Qs = cowboy_req:qs(Req0),
    PartialPathWithQs = iolist_to_binary([RestPath, <<"?">>, Qs]),
    case simple_oauth2:dispatcher(PartialPathWithQs, UrlPrefix, SocNets) of
        {redirect, Where} ->
            Secure = case Scheme of
                         <<"https">> -> true;
                         _ -> false
                     end,
            RedirectUrl = simple_oauth2:gather_url_get(Where),
            Req = cowboy_req:set_resp_cookie(<<"jwt">>, <<>>, Req0, #{domain => Host, secure => Secure, path => <<"/">>}),
            Req2 = cowboy_req:reply(302, #{<<"location">> => RedirectUrl}, <<>>, Req),
            {ok, Req2, Opts};
        {send_html, HTML} ->
            Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html; charset=utf-8">>}, HTML, Req0),
            {ok, Req, Opts};
        {ok, AuthData} ->
            %% [{id,<<"100012321321321321110">>},
            %% {email,<<"user.name@gmail.com">>},
            %% {name,<<"User Name">>},
            %% {picture,<<"https://lh6.googleusercontent.com/-aksl1123sss/BBBBBAABBBB/ABNNNNNNNNA/jjjaksksjfa/photo.jpg">>},
            %% {gender,<<"male">>},
            %% {locale,<<"en">>},
            %% {raw,[{<<"id">>,<<"100012321321321321110">>},
            %%       {<<"email">>,<<"user.name@gmail.com">>},
            %%       {<<"verified_email">>,true},
            %%       {<<"name">>,<<"User Name">>},
            %%       {<<"given_name">>,<<"User">>},
            %%       {<<"family_name">>,<<"Name">>},
            %%       {<<"link">>,<<"https://plus.google.com/100012321321321321110">>},
            %%       {<<"picture">>,
            %%        <<"https://lh6.googleusercontent.com/-aksl1123sss/BBBBBAABBBB/ABNNNNNNNNA/jjjaksksjfa/photo.jpg">>},
            %%       {<<"gender">>,<<"male">>},
            %%       {<<"locale">>,<<"en">>},
            %%       {<<"hd">>,<<"example.com">>}]},
            %% {network,<<"google">>},
            %% {access_token,<<"ya29.Gklaklskdlkalko1qioksodkoaksodko1i2031klaskdlaskdokqlkdlasdka0102o30120oskldkasldkaslko01k021k010kasolkdlaskdlaksldkasldkasl">>},
            %% {token_type,<<"Bearer">>}]
            EmailId = proplists:get_value(email, AuthData, <<>>),
            case beamparticle_auth:read_userinfo(EmailId, websocket, false) of
                {error, _} ->
                    ErrorHtml = <<"<html><body>Authentication failure. Try <a href='/auth/google/login'>again</a> or <a href='/'>start over</a>.</body>">>,
                    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html; charset=utf-8">>}, ErrorHtml, Req0),
                    {ok, Req, Opts};
                _UserInfo ->
                    JwtConfig = application:get_env(?APPLICATION_NAME, jwt, []),
                    ExpirySeconds = proplists:get_value(expiry_seconds, JwtConfig, ?DEFAULT_JWT_EXPIRY_SECONDS),
                    #{<<"access_token">> := JwtToken} = beamparticle_auth:create_jwt_auth_response(
                                                          EmailId, ExpirySeconds),
                    Secure = case Scheme of
                                 <<"https">> -> true;
                                 _ -> false
                             end,
                    %% The path is is very important in cookie, else current path is assumed
                    Req = cowboy_req:set_resp_cookie(<<"jwt">>, JwtToken, Req0,
                                                     #{domain => Host,
                                                       path => <<"/">>,
                                                       max_age => ExpirySeconds,
                                                       secure => Secure}),
                    Req2 = cowboy_req:reply(302, #{<<"location">> => <<"/">>}, <<>>, Req),
                    {ok, Req2, Opts}
            end;
        {error, Class, Reason} ->
            TextResponse = list_to_binary(io_lib:format("Error: ~p ~p~n", [Class, Reason])),
            Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; charset=utf-8">>}, TextResponse, Req0),
            {ok, Req, Opts}
    end.

