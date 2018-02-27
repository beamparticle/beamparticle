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
    lager:info("NLP Top Page received request = ~p, Opts = ~p", [Req0, Opts]),
    case Env of
        <<"2">> ->
            erlang:put(?CALL_ENV_KEY, stage);
        _ ->
            erlang:put(?CALL_ENV_KEY, prod)
    end,
    case cowboy_req:path(Req0) of
        <<"/auth/", RestPath/binary>> ->
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
                            %%Opts2 = [{jwt, JwtToken} | Opts],
                            %%render_top_page(JwtToken, Req0, Opts2, fun render_static_file_with_jwt/3)
                            %% <<"location">> => <<"/?jwt=", JwtToken/binary>>,
                            Secure = case Scheme of
                                         <<"https">> -> true;
                                         _ -> false
                                     end,
                            %% Req = cowboy_req:set_resp_cookie(<<"jwt">>, JwtToken, Req0, #{domain => Host, max_age => ExpirySeconds, secure => Secure}),
                            Req = cowboy_req:set_resp_cookie(<<"jwt">>, JwtToken, Req0,
                                                             #{domain => Host,
                                                               path => <<"/">>,  %% This is very important, else current path is assumed
                                                               max_age => ExpirySeconds,
                                                               secure => Secure}),
                            %Req = cowboy_req:set_resp_cookie(<<"jwt">>, JwtToken, Req0, #{domain => Host, path => <<"/">>}),
                            %% Req = cowboy_req:set_resp_cookie(<<"jwt">>, JwtToken, Req0, #{secure => Secure}),
                            Req2 = cowboy_req:reply(302, #{<<"location">> => <<"/">>}, <<>>, Req),
                            {ok, Req2, Opts}
                    end;
                    %%TextResponse = list_to_binary(io_lib:format("~p~n", [AuthData])),
                    %%Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; charset=utf-8">>}, TextResponse, Req0),
                    %%{ok, Req, Opts};
                {error, Class, Reason} ->
                    TextResponse = list_to_binary(io_lib:format("Error: ~p ~p~n", [Class, Reason])),
                    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; charset=utf-8">>}, TextResponse, Req0),
                    {ok, Req, Opts}
            end;
        _ ->
            %% #{jwt := JwtToken} = cowboy_req:match_qs([{jwt, [], <<>>}], Req0),
            %% Extract jwt in cookie and use it within query parameter within websocket
            %% connection, via changing the static page
            %%Cookies = cowboy_req:parse_cookies(Req0),
            %%R = case lists:keyfind(<<"jwt">>, 1, Cookies) of
            %%        {_, JwtToken} ->
            %%            Opts2 = [{jwt, JwtToken} | Opts],
            %%            render_top_page(JwtToken, Req0, Opts2, fun render_static_file_with_jwt/3);
            %%        _ ->
            %%            render_top_page(<<>>, Req0, Opts, fun render_static_file/3)
            %%    end,
            R = render_top_page(<<>>, Req0, Opts, fun render_static_file/3),
            erlang:erase(?CALL_ENV_KEY),
            R
    end.


render_top_page(JwtToken, Req0, Opts, Fun) ->
    %% Note that nlpfn_top_page/2 must look for
    %% {jwt, _} in Opts for any jwt token which must
    %% be taken into consideration.
    case beamparticle_dynamic:execute({<<"nlpfn_top_page">>,
                                       [Req0, Opts]}) of
        {ok, {Body, RespHeaders}} when (is_list(Body) orelse
                                        is_binary(Body)) andalso
                                       is_map(RespHeaders) ->
            Req = cowboy_req:reply(200, RespHeaders, Body, Req0),
            {ok, Req, Opts};
        {ok, {Code, Body, RespHeaders}} when is_integer(Code) andalso
                                             (is_list(Body) orelse
                                              is_binary(Body)) andalso
                                             is_map(RespHeaders) ->
            Req = cowboy_req:reply(Code, RespHeaders, Body, Req0),
            {ok, Req, Opts};
        {ok, Req} ->
            %% the dynamic function automatically sent the reply
            %% so we dont have to.
            %% More power to dynamic functions for sending replies
            %% in many different ways (regular, streaming, chuncked, etc).
            {ok, Req, Opts};
        _ ->
            {Req, Opts} = Fun(JwtToken, Req0, Opts),
            {ok, Req, Opts}
    end.


render_static_file(_JwtToken, Req0, Opts) ->
    PrivDir = code:priv_dir(?APPLICATION_NAME),
    File = PrivDir ++ "/index-nlp.html",
    Size = filelib:file_size(File),
    Req = cowboy_req:reply(200, #{}, {sendfile, 0, Size, File}, Req0),
    {Req, Opts}.

%%render_static_file_with_jwt(JwtToken, Req0, Opts) ->
%%    PrivDir = code:priv_dir(?APPLICATION_NAME),
%%    Filename = PrivDir ++ "/index-nlp.html",
%%    {ok, Content} = file:read_file(Filename),
%%    PageHtmlIoList = string:replace(Content, <<"JWT_ENCODED_TOKEN">>, JwtToken, all),
%%    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html; charset=utf-8">>}, PageHtmlIoList, Req0),
%%    {Req, Opts}.

