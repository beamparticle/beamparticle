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
-module(beamparticle_highperf_http_handler).

-behaviour(ranch_protocol).

-include("beamparticle_constants.hrl").

%% API
-export([start_link/4]).
-export([init/4]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================

%%%===================================================================
%%% ranch_protocol callbacks
%%%===================================================================

start_link(Ref, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
	{ok, Pid}.

init(Ref, Socket, Transport, Opts) ->
	ok = ranch:accept_ack(Ref),
    {ok, {InetIp, InetPort}} = Transport:peername(Socket),
    IpBinary = list_to_binary(inet:ntoa(InetIp)),
    PortBinary = integer_to_binary(InetPort),
	loop(Socket, Transport, Opts, IpBinary, PortBinary, []).

loop(Socket, Transport, Opts, IpBinary, PortBinary, PartialDataList) ->
    MaxBodyBytes = proplists:get_value(max_read_length, Opts, 5000),
    MaxReadTimeoutMsec = proplists:get_value(max_read_timeout_msec, Opts, 5000),
	case Transport:recv(Socket, 0, MaxReadTimeoutMsec) of
		{ok, Data} when byte_size(Data) > 0 ->
            Parsed = parse_http_request(Data, PartialDataList),
            %%lager:debug("highperf transport Parsed = ~p, Data = ~p, PartialDataList = ~p", [Parsed, Data, PartialDataList]),
            case Parsed of
                {HttpMethod, <<"/post/", RestPath/binary>> = _RequestPath,
                 _HttpVersion, RequestHeaders, RequestBody} when
                      HttpMethod == <<"POST">> orelse
                      HttpMethod == <<"post">> ->
                    LowerRequestHeaders = string:lowercase(RequestHeaders),
                    ContentLength = request_content_length(LowerRequestHeaders),
                    R = process_http_post(RequestBody, RestPath,
                                          Data, PartialDataList, MaxBodyBytes, LowerRequestHeaders, ContentLength),
                    case R of
                        {ok, {loop, Content}} ->
                            send_http_response(Socket, Transport, Content, keep_alive),
                            loop(Socket, Transport, Opts, IpBinary, PortBinary, []);
                        {ok, {close, Content}} ->
                            send_http_response(Socket, Transport, Content, close),
                            ok = Transport:close(Socket);
                        {ok, NewPartialDataList} ->
                            loop(Socket, Transport, Opts, IpBinary, PortBinary,
                                 NewPartialDataList);
                        {error, close} ->
                            ok = Transport:close(Socket)
                    end;
                {HttpMethod, <<"/api/", RestPath/binary>> = _RequestPath,
                 _HttpVersion, RequestHeaders, RequestBody} when
                      HttpMethod == <<"POST">> orelse
                      HttpMethod == <<"post">> orelse
                      HttpMethod == <<"GET">> orelse
                      HttpMethod == <<"get">> ->
                    IsGet = case HttpMethod of
                                <<"GET">> -> true;
                                <<"get">> -> true;
                                _ -> false
                            end,
                    LowerRequestHeaders = string:lowercase(RequestHeaders),
                    {BodyData, ContentLength} = case IsGet of
                                   true ->
                                       {_FunctionName, QsParamsBin} = extract_function_and_params(RestPath),
                                       QsParamParts = string:split(QsParamsBin, <<"&">>, all),
                                       BodyAsTupleList =
                                       lists:foldl(fun(<<>>, AccIn) ->
                                                           AccIn;
                                                      (E, AccIn) ->
                                                           case string:split(E, <<"=">>) of
                                                               [A] ->
                                                                   [{A, <<"1">>} | AccIn];
                                                               [A, B] ->
                                                                   [{A, B} | AccIn]
                                                           end
                                                   end, [], QsParamParts),
                                       GetBody = jiffy:encode(maps:from_list(BodyAsTupleList)),
                                       {GetBody, byte_size(GetBody)};
                                   false ->
                                       PostContentLength = request_content_length(LowerRequestHeaders),
                                       {RequestBody, PostContentLength}
                               end,
                    R = process_http_post(BodyData, RestPath,
                                          Data, PartialDataList, MaxBodyBytes, LowerRequestHeaders, ContentLength),
                    case R of
                        {ok, {loop, Content}} ->
                            send_http_response(Socket, Transport, Content, keep_alive),
                            loop(Socket, Transport, Opts, IpBinary, PortBinary, []);
                        {ok, {close, Content}} ->
                            send_http_response(Socket, Transport, Content, close),
                            ok = Transport:close(Socket);
                        {ok, NewPartialDataList} ->
                            loop(Socket, Transport, Opts, IpBinary, PortBinary,
                                 NewPartialDataList);
                        {error, close} ->
                            ok = Transport:close(Socket)
                    end;
                {<<"GET">>, <<"/health">>, _HttpVersion, RequestHeaders, _RequestBody} ->
                    {ok, DateTimeBinary} =
                        beamparticle_date_server:datetime(binary),
                    %%Content = <<"{\"msg\": \"I am alive\", \"datetime\": \"",
                    %%            DateTimeBinary/binary,
                    %%            "\", \"ip\": \"",
                    %%            IpBinary/binary,
                    %%            "\", \"port\": ", PortBinary/binary,
                    %%            "}">>,
                    Content = [<<"{\"msg\": \"I am alive\", \"datetime\": \"">>,
                                DateTimeBinary,
                                <<"\", \"ip\": \"">>,
                                IpBinary,
                                <<"\", \"port\": ">>,
                                PortBinary,
                                <<"}">>],
                    LowerRequestHeaders = string:lowercase(RequestHeaders),
                    case string:find(LowerRequestHeaders, <<"connection: keep-alive">>) of
                        nomatch ->
                            send_http_response(Socket, Transport, Content, close),
                            ok = Transport:close(Socket);
                        _ ->
                            send_http_response(Socket, Transport, Content, keep_alive),
                            loop(Socket, Transport, Opts, IpBinary, PortBinary, [])
                    end;
                {_HttpMethod, _RequestPath, _HttpVersion, incomplete} ->
                    NewPartialDataList = [Data | PartialDataList],
                    TotalBytes = lists:foldl(fun(V, AccIn) ->
                                                     byte_size(V) + AccIn
                                             end, 0, NewPartialDataList),
                    case TotalBytes > MaxBodyBytes of
                        false ->
                            loop(Socket, Transport, Opts, IpBinary, PortBinary,
                                 [Data | PartialDataList]);
                        true ->
                            ok = Transport:close(Socket)
                    end;
                {error, incomplete} ->
                    loop(Socket, Transport, Opts, IpBinary, PortBinary,
                         [Data | PartialDataList]);
                %%{error, bad_http_first_line}
                _ ->
                    ok = Transport:close(Socket)
            end;
		_ ->
            %% apart from read timeout or errors, well reach here when client
            %% disconnected
			ok = Transport:close(Socket)
    end.

parse_http_request(Data, PartialDataList) ->
    NewData = case PartialDataList of
                  [] -> Data;
                  _ -> iolist_to_binary(lists:reverse([Data | PartialDataList]))
              end,
    %% use lists:flatten/1 after string:split/2 when NewDate is [binary()],
    %% but at present NewDate is formed as binary()
    case string:split(NewData, <<"\r\n">>) of
        [FirstLine, Rest] ->
            TrimmedFirstLine = string:trim(FirstLine),
            case string:split(TrimmedFirstLine, <<" ">>, all) of
                [HttpMethod, RequestPath, HttpVersion] ->
                    case Rest of
                        <<"\r\n", RequestBody/binary>> ->
                            RequestHeaders = <<>>,
                            {HttpMethod, RequestPath, HttpVersion, RequestHeaders, RequestBody};
                        _ ->
                            case string:split(Rest, <<"\r\n\r\n">>) of
                                [RequestHeaders, RequestBody] ->
                                    {HttpMethod, RequestPath, HttpVersion, RequestHeaders, RequestBody};
                                _ ->
                                    {HttpMethod, RequestPath, HttpVersion, incomplete}
                            end
                    end;
                _E ->
                    %%lager:debug("bad_http_first_line, E = ~p", [E]),
                    {error, bad_http_first_line}
            end;
        _ ->
            {error, incomplete}
    end.

send_http_response(Socket, Transport, Content, keep_alive) ->
    ContentLength = case is_binary(Content) of
                        true -> byte_size(Content);
                        false ->
                            lists:foldl(fun(X, AccIn) ->
                                                byte_size(X) + AccIn
                                        end, 0, Content)
                    end,
    Response = [<<"HTTP/1.1 200 OK\r\ncontent-length: ">>, 
                integer_to_binary(ContentLength),
                <<"\r\ncontent-type: application/json\r\n">>,
                <<"connection: keep-alive\r\n">>,
                <<"\r\n">>,
                Content],
    Transport:send(Socket, Response);
send_http_response(Socket, Transport, Content, _) ->
    ContentLength = case is_binary(Content) of
                        true -> byte_size(Content);
                        false ->
                            lists:foldl(fun(X, AccIn) ->
                                                byte_size(X) + AccIn
                                        end, 0, Content)
                    end,

    Response = [<<"HTTP/1.1 200 OK\r\ncontent-length: ">>, 
                integer_to_binary(ContentLength),
                <<"\r\ncontent-type: application/json\r\n">>,
                <<"\r\n">>,
                Content],
    Transport:send(Socket, Response).

%%minimal_loop(Socket, Transport, Opts) ->
%%    MaxBodyBytes = proplists:get_value(max_read_length, Opts, 5000),
%%	case Transport:recv(Socket, 0, MaxBodyBytes) of
%%		{ok, Data} when byte_size(Data) > 4 ->
%%            Content = <<"I am alive">>,
%%            ContentLength = byte_size(Content),
%%            Response = [<<"HTTP/1.1 200 OK\r\ncontent-length: ">>, 
%%                        integer_to_binary(ContentLength),
%%                        <<"\r\n">>,
%%                        <<"connection: keep-alive\r\n">>,
%%                        <<"\r\n">>,
%%                        Content],
%%			Transport:send(Socket, Response),
%%			ok = Transport:close(Socket);
%%			%% loop(Socket, Transport);
%%		_ ->
%%			ok = Transport:close(Socket)
%%   end.

request_content_length(LowerRequestHeaders) ->
    case string:find(LowerRequestHeaders, <<"content-length:">>) of
        <<"content-length:", RestContentLength/binary>> ->
            case string:split(RestContentLength, <<"\r\n">>) of
                [ContentLengthBin | _] ->
                    binary_to_integer(string:trim(ContentLengthBin));
                _ ->
                    -1
            end;
        _ ->
            0
    end.

data_bytes(Data) ->
    lists:foldl(fun(V, AccIn) -> byte_size(V) + AccIn end, 0, Data).

extract_function_and_params(RestPath) ->
    [FunctionName | InputQsParams] = string:split(RestPath, <<"?">>),
    QsParamsBin = case InputQsParams of
                      [] -> <<>>;
                      [InputQsParamBin] -> http_uri:decode(InputQsParamBin)
                  end,
    {FunctionName, QsParamsBin}.

is_keepalive(LowerRequestHeaders) ->
    case string:find(LowerRequestHeaders, <<"connection: keep-alive">>) of
        nomatch -> false;
        _ -> true
    end.

process_http_post(RequestBody, RestPath, Data, PartialDataList, MaxBodyBytes, LowerRequestHeaders, ContentLength) ->
    case ContentLength > byte_size(RequestBody) of
        true ->
            NewPartialDataList = [Data | PartialDataList],
            TotalBytes = data_bytes(NewPartialDataList),
            case TotalBytes > MaxBodyBytes of
                false ->
                    %%loop(Socket, Transport, Opts, IpBinary, PortBinary,
                    %%     [Data | PartialDataList]);
                    {ok, [Data | PartialDataList]};
                true ->
                    %%ok = Transport:close(Socket)
                    {error, close}
            end;
        false ->
            {FunctionName, QsParamsBin} = extract_function_and_params(RestPath),
            QsParamParts = string:split(QsParamsBin, <<"&">>, all),
            erlang:erase(?LOG_ENV_KEY),
            case lists:filter(fun(E) -> E =:= <<"env=2">> end, QsParamParts) of
                [] ->
                    erlang:put(?CALL_ENV_KEY, prod);
                _ ->
                    erlang:put(?CALL_ENV_KEY, stage)
            end,
            Arguments = [RequestBody,
                         <<"{\"qs\": \"",
                           QsParamsBin/binary,
                           "\"}">>],
            Content = beamparticle_dynamic:get_raw_result(
                        FunctionName, Arguments),
            %% as part of dynamic call configurations could be set,
            %% so lets erase that before the next reuse
            beamparticle_dynamic:erase_config(),
            case is_keepalive(LowerRequestHeaders) of
                false ->
                    %%send_http_response(Socket, Transport, Content, close),
                    %%ok = Transport:close(Socket);
                    {ok, {close, Content}};
                true ->
                    %%send_http_response(Socket, Transport, Content, keep_alive),
                    %% loop(Socket, Transport, Opts, IpBinary, PortBinary, [])
                    {ok, {loop, Content}}
            end
    end.

