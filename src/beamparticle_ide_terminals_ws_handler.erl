%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%%
%%% Terminal Emulation References taken from xterm.js project
%%% https://github.com/xtermjs/xterm.js/blob/master/src/Terminal.ts
%%% https://github.com/xtermjs/xterm.js/blob/master/src/Charsets.ts
%%% https://github.com/BobReid/xterm.js/blob/master/src/xterm.js
%%%
%%%  * http://vt100.net/
%%%  * http://invisible-island.net/xterm/ctlseqs/ctlseqs.txt
%%%  * http://invisible-island.net/xterm/ctlseqs/ctlseqs.html
%%%  * http://invisible-island.net/vttest/
%%%  * http://www.inwap.com/pdp10/ansicode.txt
%%%  * http://linux.die.net/man/4/console_codes
%%%  * http://linux.die.net/man/7/urxvt
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
-module(beamparticle_ide_terminals_ws_handler).
-author("neerajsharma").

-include("beamparticle_constants.hrl").

%% API

-export([init/2]).
-export([
  websocket_handle/2,
  websocket_info/2,
  websocket_init/1
]).

-export([run_command/2]).
-export([linked/3, close_terminal/2]).

-export([tty_prompt/0, tty_color/1,
        tty_clear_line/1]).

%% @doc inform the terminal about the link
-spec linked(pid(), integer(), pid()) -> ok.
linked(TerminalPid, Id, Pid) ->
    TerminalPid ! {linked, Id, Pid}.

%% @doc inform the terminal to shutdown
-spec close_terminal(pid(), integer()) -> ok.
close_terminal(TerminalPid, Id) ->
    TerminalPid ! {close_terminal, Id}.

%% websocket over http
%% see https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_websocket/
init(Req, State) ->
    Opts = #{
      idle_timeout => 86400000},  %% 24 hours
    %% userinfo must be a map of user meta information
    Cookies = cowboy_req:parse_cookies(Req),
    Token = case lists:keyfind(<<"jwt">>, 1, Cookies) of
                {_, CookieJwtToken} -> CookieJwtToken;
                _ -> <<>>
            end,
    %% Do not handle case when id is anything other than integer and crash.
    Id = binary_to_integer(cowboy_req:binding(id, Req)),
    lager:info("[~p] ~p init(~p, ~p), Id = ~p", [self(), ?MODULE, Req, State, Id]),
    State2 = case Token of
                 <<>> ->
                    [{id, Id}, {command, <<>>}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                 _ ->
                     JwtToken = string:trim(Token),
                     case beamparticle_auth:decode_jwt_token(JwtToken) of
                         {ok, Claims} ->
                             %% TODO validate jwt iss
                             #{<<"sub">> := Username} = Claims,
                             case beamparticle_auth:read_userinfo(Username, websocket, false) of
                                 {error, _} ->
                                     [{id, Id}, {command, <<>>}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State];
                                 UserInfo ->
                                     [{id, Id}, {command, <<>>}, {calltrace, false}, {userinfo, UserInfo}, {dialogue, []} | State]
                             end;
                         _ ->
                            [{id, Id}, {command, <<>>}, {calltrace, false}, {userinfo, undefined}, {dialogue, []} | State]
                     end
             end,
    {cowboy_websocket, Req, State2, Opts}.

%handle(Req, State) ->
%  lager:debug("Request not expected: ~p", [Req]),
%  {ok, Req2} = cowboy_http_req:reply(404, [{'Content-Type', <<"text/html">>}]),
%  {ok, Req2, State}.

%% In case you need to initialize use websocket_init/1 instead
%% of init/2.
websocket_init(State) ->
    %% Notice that init/2 is not called within the websocket actor,
    %% which websocket_init/1 is in the connected actor, so any
    %% changes to process dictionary here is correct.
    lager:info("[~p] ~p init websocket", [self(), ?MODULE]),
    Id = proplists:get_value(id, State),
    {ok, ShellTerminalPid} = beamparticle_ide_terminals_server:read(Id),
    %% TODO save this pid for fast access
    erlang:link(ShellTerminalPid),
    %% TODO track via timer
    beamparticle_ide_shellterminal_ws_handler:terminal_started(
      ShellTerminalPid, Id, self()),
    {ok, State}.

websocket_handle({text, Command}, State) ->
    case proplists:get_value(userinfo, State) of
        undefined ->
            %% do not reply unless authenticated
            {ok, State, hibernate};
        _UserInfo ->
			run_command(Command, State)
    end;
websocket_handle(Text, State) when is_binary(Text) ->
    %% sometimes the text is received directly as binary,
    %% so re-route it to core handler.
    websocket_handle({text, Text}, State).

websocket_info({timeout, _Ref, Msg}, State) ->
    {reply, {text, Msg}, State, hibernate};
websocket_info({linked, Id, Pid} = Info, State) ->
    case proplists:get_value(id, State) of
        Id ->
            lager:info("[~p] ~p websocket linked event = ~p", [self(), ?MODULE, Info]),
			Frames = [{text, ?DEFAULT_IDE_TERMINAL_WELCOME},
                      {text, iolist_to_binary([<<"@terminal #">>,
                                               integer_to_binary(Id),
                                               <<" and @pid ">>,
                                               list_to_binary(pid_to_list(self())),
                                               <<" / ">>,
                                               list_to_binary(pid_to_list(Pid)),
                                               <<"\r\n">>])},
                      {text, list_to_binary(tty_prompt())}],
                      %% {text, ?DEFAULT_IDE_TERMINAL_PROMPT}],
            {reply, Frames, State, hibernate};
        _OtherId ->
            lager:info("[~p] ~p websocket with State = ~p incorrectly received linked event = ~p",
                       [self(), ?MODULE, State, Info]),
            {ok, State, hibernate}
    end;
websocket_info({close_terminal, Id} = Info, State) ->
    case proplists:get_value(id, State) of
        Id ->
            lager:info("websocket received close_terminal event = ~p", [Info]),
            {stop, State};
        _OtherId ->
            lager:info("websocket with State = ~p incorrectly received close_terminal event = ~p", [State, Info]),
            {ok, State, hibernate}
    end;
websocket_info(_Info, State) ->
    lager:debug("websocket info"),
    {ok, State, hibernate}.


% terminate is missing

%%%===================================================================
%%% Internal
%%%===================================================================

%% Notice that that echo to the client is important, otherwise
%% it will not display to its screen.
run_command(Command, State) ->
    %% TODO process the command when the command terminator
    %% is provided, else just echo back to the user
    %% TODO when user types "enter" key then only \r is received
    %% here, but we will have to convert that to \r\n when sending
    %% it back.
    %% TODO: report it to mailing list
    %% Notice a bug in Erlag string:split/3
    %% 12> string:split(<<"anncacsa\rnasndkasd\nansdas\r\nasdasdas">>, "\r", all).    
    %% [<<"anncacsa">>,<<"nasndkasd\nansdas\r\nasdasdas">>]
    %%
    %% The following works though:
    %% 19> string:split(<<"anncacsa\rnasndkasdansdas\r \nasdasdas">>, "\r", all). 
    %% [<<"anncacsa">>,<<"nasndkasdansdas">>,<<" \nasdasdas">>]
    %%
    %% For backspace the Command would be 0x7f (DEL) but the response from
    %% server must be \b which is 0x08 or better \b\x1b[K, which will move
    %% the cursor one column to the left and clear the line to the right.
    %%
    PartialCommand = proplists:get_value(command, State),
    {Resp, PartialCommand4, State4} = case {Command, PartialCommand} of
                                  {<<16#7f>>, <<>>} ->
                                      {<<>>, PartialCommand, State};
                                  {<<16#7f>>, _} ->
                                      TotalLen = byte_size(PartialCommand),
                                      PartialCommand2 = binary:part(PartialCommand, 0, TotalLen - 1),
                                      %% quick hack for handling DEL key which is received
                                      %% when user depresses backspace (for some keyboards)
                                      {list_to_binary([tty_backspace() | tty_clear_line(eol)]),
                                       PartialCommand2, State};
                                  {<<$\t>>, _} ->
                                              %% TODO No auto-completing for tab at present
                                              {<<>>, PartialCommand, State};
                                  _ ->
                                      BinPrompt = list_to_binary(tty_prompt()),
                                      Lines = string:split(Command, <<"\r">>, all),
                                      case Lines of
                                          [<<>>] ->
                                              R2 = execute_command([PartialCommand], [], State),
                                              {[], RespAccIn, State2} = R2,
                                              lager:info("~p", [R2]),
                                              FinalResp = build_shell_response(RespAccIn, PartialCommand, BinPrompt),
                                              %FinalResp = iolist_to_binary(lists:join(<<"\r\n">>, lists:flatten([[<<"\r\n">>, BinPrompt, X, <<"\r\n">>, Y] || {X, Y} <- RespAccIn]))),
                                              {FinalResp, <<>>, State2};
                                              %% {iolist_to_binary([<<"\r\n", BinPrompt/binary>>]), <<>>};
                                          [A] ->
                                              {A, iolist_to_binary([PartialCommand, A]), State};
                                          [_|_] ->
                                              PartialCommand3 = lists:last(Lines),
                                              [HLine | RestLines] = lists:droplast(Lines),
                                              Lines2 = [iolist_to_binary([PartialCommand, HLine]) | RestLines],
                                              R3 = execute_command(Lines2, [], State),
                                              {[], RespAccIn2, State3} = R3,
                                              lager:info("~p", [R3]),
                                              %% FinalResp2 = iolist_to_binary(lists:join(<<"\r\n">>, lists:flatten([[<<"\r\n">>, BinPrompt, X, <<"\r\n">>, Y] || {X, Y} <- RespAccIn2]))),
                                              FinalResp2 = build_shell_response(RespAccIn2, PartialCommand, BinPrompt),
                                              {FinalResp2, PartialCommand3, State3}
                                              %%{iolist_to_binary(lists:join(<<"\r\n", BinPrompt/binary>>, Lines)),
                                              %% PartialCommand3}
                                      end
                              end,
    State5 = proplists:delete(command, State4),
    State6 = [{command, PartialCommand4} | State5],
    %% Resp = Command,
    {reply, {text, Resp}, State6, hibernate}.


execute_command([], ResponseAccIn, State) ->
    {[], ResponseAccIn, State};
execute_command([<<>>], ResponseAccIn, State) ->
    {[], ResponseAccIn, State};
%%execute_command([H], ResponseAccIn, State) ->
%%    {[H], ResponseAccIn, State};
execute_command([H | Rest], ResponseAccIn, State) ->
    TrimmedH = string:trim(H),
    {Response, State2} = execute(TrimmedH, State),
    execute_command(Rest, [{H, Response} | ResponseAccIn], State2).


execute(<<>>, State) ->
    {<<>>, State};
execute(Text, State) ->
    FunctionBody = beamparticle_erlparser:create_anonymous_function(Text),
    R = beamparticle_ws_handler:handle_run_command(FunctionBody, State),
    {reply, {text, JsonRespBin}, State2, hibernate} = R,
    PrettyJsonResp = jiffy:encode(jiffy:decode(JsonRespBin, [return_maps]), [pretty]),
    PrettyJsonForTerminal = binary:replace(PrettyJsonResp, <<"\n">>, <<"\r\n">>, [global]),
    {PrettyJsonForTerminal, State2}.
    %% {JsonRespBin, State2}.


build_shell_response([], _PartialCommand, BinPrompt) ->
    <<"\r\n", BinPrompt/binary>>;
build_shell_response(RespList, PartialCommand, BinPrompt) ->
    [{HCmd, HResp} | Rest] = RespList,
    PartialCommandLen = byte_size(PartialCommand),
    R1 = case HCmd of
             PartialCommand ->
                 iolist_to_binary([<<"\r\n">>, HResp]);
        <<PartialCommand:PartialCommandLen/binary, RestCommand/binary>> ->
                 iolist_to_binary([RestCommand, <<"\r\n">>, HResp])
         end,
    R2 = lists:flatten([[<<"\r\n">>, BinPrompt, X, <<"\r\n">>, Y] || {X, Y} <- Rest]),
    iolist_to_binary([R1, <<"\r\n">>, BinPrompt | R2]).


%% http://erlang.org/doc/apps/stdlib/unicode_usage.html
%% https://www.fileformat.info/info/unicode/char/03bb/index.htm
%% This is same as
%% ```
%% unicode:characters_to_binary([16#03bb])
%% '''
%% Note that unicode in Erlang uses utf-8 by default.
tty_prompt() ->
    [16#ce, 16#bb, " "].

%% http://wiki.bash-hackers.org/scripting/terminalcodes
tty_backspace() ->
    [$\b].

%% escape char can be sent as \e instead of 16#1b
tty_clear_line(eol) ->
    [16#1b | "[K"];
tty_clear_line(cob) ->
    [16#1b | "[1K"];
tty_clear_line(whole) ->
    [16#1b | "[2K"].

%% http://www.lihaoyi.com/post/BuildyourownCommandLinewithANSIescapecodes.html
tty_color(black) -> [16#001b | "[30m"];
tty_color(red) -> [16#001b | "[31m"];
tty_color(green) -> [16#001b | "[32m"];
tty_color(yellow) -> [16#001b | "[33m"];
tty_color(blue) -> [16#001b | "[34m"];
tty_color(magenta) -> [16#001b | "[35m"];
tty_color(cyan) -> [16#001b | "[36m"];
tty_color(white) -> [16#001b | "[37m"];
tty_color(reset) -> [16#001b | "[0m"].


