%%%-------------------------------------------------------------------
%%% @doc A callback module for `gen_smtp_server_session' for
%%% implementing smtp server.
%%% Copied from https://github.com/Vagabond/gen_smtp/blob/master/src/smtp_server_example.erl
%%% @end
%%%-------------------------------------------------------------------
-module(beamparticle_smtp_server).
-behaviour(gen_smtp_server_session).

-include("beamparticle_constants.hrl").

-export([init/4, handle_HELO/2, handle_EHLO/3, handle_MAIL/2, handle_MAIL_extension/2,
    handle_RCPT/2, handle_RCPT_extension/2, handle_DATA/4, handle_RSET/1, handle_VRFY/2,
    handle_other/3, handle_AUTH/4, handle_STARTTLS/1, handle_info/2,
    code_change/3, terminate/2]).

-define(RELAY, false).
%% -define(RELAY, true).

-record(state,
    {
        options = [] :: list()
    }).

-type(error_message() :: {'error', string(), #state{}}).

%% @doc Initialize the callback module's state for a new session.
%% The arguments to the function are the SMTP server's hostname (for use in the SMTP anner),
%% The number of current sessions (eg. so you can do session limiting), the IP address of the
%% connecting client, and a freeform list of options for the module. The Options are extracted
%% from the `callbackoptions' parameter passed into the `gen_smtp_server_session' when it was
%% started.
%%
%% If you want to continue the session, return `{ok, Banner, State}' where Banner is the SMTP
%% banner to send to the client and State is the callback module's state. The State will be passed
%% to ALL subsequent calls to the callback module, so it can be used to keep track of the SMTP
%% session. You can also return `{stop, Reason, Message}' where the session will exit with Reason
%% and send Message to the client.
-spec init(Hostname :: binary(), SessionCount :: non_neg_integer(), Address :: tuple(), Options :: list()) -> {'ok', string(), #state{}} | {'stop', any(), string()}.
init(Hostname, SessionCount, Address, Options) ->
    lager:info("peer: ~p", [Address]),
    case SessionCount > 20 of
        false ->
            Banner = [Hostname, " ESMTP smtp_server"],
            State = #state{options = Options},
            {ok, Banner, State};
        true ->
            lager:info("Connection limit exceeded"),
            {stop, normal, ["421 ", Hostname, " is too busy to accept mail right now"]}
    end.

%% @doc Handle the HELO verb from the client. Arguments are the Hostname sent by the client as
%% part of the HELO and the callback State.
%%
%% Return values are `{ok, State}' to simply continue with a new state, `{ok, MessageSize, State}'
%% to continue with the SMTP session but to impose a maximum message size (which you can determine
%% , for example, by looking at the IP address passed in to the init function) and the new callback
%% state. You can reject the HELO by returning `{error, Message, State}' and the Message will be
%% sent back to the client. The reject message MUST contain the SMTP status code, eg. 554.
-spec handle_HELO(Hostname :: binary(), State :: #state{}) -> {'ok', pos_integer(), #state{}} | {'ok', #state{}} | error_message().
handle_HELO(<<"invalid">>, State) ->
    % contrived example
    {error, "554 invalid hostname", State};
handle_HELO(<<"trusted_host">>, State) ->
    {ok, State}; %% no size limit because we trust them.
handle_HELO(Hostname, State) ->
    lager:info("HELO from ~s", [Hostname]),
    {ok, 655360, State}. % 640kb of HELO should be enough for anyone.
    %If {ok, State} was returned here, we'd use the default 10mb limit

%% @doc Handle the EHLO verb from the client. As with EHLO the hostname is provided as an argument,
%% but in addition to that the list of ESMTP Extensions enabled in the session is passed. This list
%% of extensions can be modified by the callback module to add/remove extensions.
%%
%% The return values are `{ok, Extensions, State}' where Extensions is the new list of extensions
%% to use for this session or `{error, Message, State}' where Message is the reject message as
%% with handle_HELO.
-spec handle_EHLO(Hostname :: binary(), Extensions :: list(), State :: #state{}) -> {'ok', list(), #state{}} | error_message().
handle_EHLO(<<"invalid">>, _Extensions, State) ->
    % contrived example
    {error, "554 invalid hostname", State};
handle_EHLO(Hostname, Extensions, State) ->
    lager:info("EHLO from ~s", [Hostname]),
    % You can advertise additional extensions, or remove some defaults
    MyExtensions = case proplists:get_value(auth, State#state.options, false) of
        true ->
            % auth is enabled, so advertise it
            Extensions ++ [{"AUTH", "PLAIN LOGIN CRAM-MD5"}, {"STARTTLS", true}];
        false ->
            Extensions
    end,
    {ok, MyExtensions, State}.

%% @doc Handle the MAIL FROM verb. The From argument is the email address specified by the
%% MAIL FROM command. Extensions to the MAIL verb are handled by the `handle_MAIL_extension'
%% function.
%%
%% Return values are either `{ok, State}' or `{error, Message, State}' as before.
-spec handle_MAIL(From :: binary(), State :: #state{}) -> {'ok', #state{}} | error_message().
handle_MAIL(<<"badguy@blacklist.com">>, State) ->
    %% TODO blacklist email addresses
    {error, "552 go away", State};
handle_MAIL(From, State) ->
    lager:info("Mail from ~s", [From]),
    % you can accept or reject the FROM address here
    {ok, State}.

%% @doc Handle an extension to the MAIL verb. Return either `{ok, State}' or `error' to reject
%% the option.
-spec handle_MAIL_extension(Extension :: binary(), State :: #state{}) -> {'ok', #state{}} | 'error'.
handle_MAIL_extension(<<"X-SomeExtension">> = Extension, State) ->
    lager:info("Mail from extension ~s", [Extension]),
    % any MAIL extensions can be handled here
    {ok, State};
handle_MAIL_extension(Extension, _State) ->
    lager:info("Unknown MAIL FROM extension ~s", [Extension]),
    error.

-spec handle_RCPT(To :: binary(), State :: #state{}) -> {'ok', #state{}} | {'error', string(), #state{}}.
handle_RCPT(<<"nobody@example.com">>, State) ->
    %% TODO blacklist email address where the email lands to which are not known
    %% in the system
    {error, "550 No such recipient", State};
handle_RCPT(To, State) ->
%% handle_RCPT(<<"pixie@pixieee.com">> = To, State) ->
    lager:info("Mail to ~s", [To]),
    [Username, ReceivedDomain] = binary:split(To, <<"@">>),
    case binary:split(To, <<"@">>) of
        [Username, ReceivedDomain] ->
            SmtpConfig = application:get_env(?APPLICATION_NAME, smtp, []),
            Domain = proplists:get_value(domain, SmtpConfig),
            case binary_to_list(ReceivedDomain) of
                Domain ->
                    %% you can accept or reject RCPT TO addesses here, one per call
                    {ok, State};
            _ ->
                    {error, "550 No such recipient", State}
            end;
        _ ->
            {error, "550 No such recipient", State}
    end.

-spec handle_RCPT_extension(Extension :: binary(), State :: #state{}) -> {'ok', #state{}} | 'error'.
handle_RCPT_extension(<<"X-SomeExtension">> = Extension, State) ->
    % any RCPT TO extensions can be handled here
    lager:info("Mail to extension ~s", [Extension]),
    {ok, State};
handle_RCPT_extension(Extension, _State) ->
    lager:info("Unknown RCPT TO extension ~s", [Extension]),
    error.

-spec handle_DATA(From :: binary(), To :: [binary(),...], Data :: binary(), State :: #state{}) -> {'ok', string(), #state{}} | {'error', string(), #state{}}.
handle_DATA(_From, _To, <<>>, State) ->
    {error, "552 Message too small", State};
handle_DATA(From, To, Data, State) ->
    % some kind of unique id
    Reference = lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X>> <= erlang:md5(term_to_binary(unique_id()))]),
    % if RELAY is true, then relay email to email address, else send email data to console
    case proplists:get_value(relay, State#state.options, false) of
        true -> relay(From, To, Data);
        false ->
            lager:info("message from ~s to ~p queued as ~s, body length ~p", [From, To, Reference, byte_size(Data)]),
            beamparticle_smtp_util:save_email_file(Data, Reference),
            case proplists:get_value(parse, State#state.options, false) of
                false -> ok;
                true ->
                    try mimemail:decode(Data) of
                        _Result ->
                            lager:info("Message decoded successfully!")
                    catch
                        What:Why ->
                            lager:info("Message decode FAILED with ~p:~p", [What, Why]),
                            case proplists:get_value(dump, State#state.options, false) of
                            false -> ok;
                            true ->
                                %% optionally dump the failed email somewhere for analysis
                                File = "dump/"++Reference,
                                case filelib:ensure_dir(File) of
                                    ok ->
                                        file:write_file(File, Data);
                                    _ ->
                                        ok
                                end
                            end
                    end
            end
    end,
    % At this point, if we return ok, we've accepted responsibility for the email
    {ok, Reference, State}.

-spec handle_RSET(State :: #state{}) -> #state{}.
handle_RSET(State) ->
    % reset any relevant internal state
    State.

-spec handle_VRFY(Address :: binary(), State :: #state{}) -> {'ok', string(), #state{}} | {'error', string(), #state{}}.
handle_VRFY(<<"someuser">>, State) ->
    {ok, "someuser@"++smtp_util:guess_FQDN(), State};
handle_VRFY(_Address, State) ->
    {error, "252 VRFY disabled by policy, just send some mail", State}.

-spec handle_other(Verb :: binary(), Args :: binary(), #state{}) -> {string(), #state{}}.
handle_other(Verb, _Args, State) ->
    % You can implement other SMTP verbs here, if you need to
    {["500 Error: command not recognized : '", Verb, "'"], State}.

%% this callback is OPTIONAL
%% it only gets called if you add AUTH to your ESMTP extensions
-spec handle_AUTH(Type :: 'login' | 'plain' | 'cram-md5', Username :: binary(), Password :: binary() | {binary(), binary()}, #state{}) -> {'ok', #state{}} | 'error'.
handle_AUTH(Type, <<"username">>, <<"PaSSw0rd">>, State) when Type =:= login; Type =:= plain ->
    {ok, State};
handle_AUTH('cram-md5', <<"username">>, {Digest, Seed}, State) ->
    case smtp_util:compute_cram_digest(<<"PaSSw0rd">>, Seed) of
        Digest ->
            {ok, State};
        _ ->
            error
    end;
handle_AUTH(_Type, _Username, _Password, _State) ->
    error.

%% this callback is OPTIONAL
%% it only gets called if you add STARTTLS to your ESMTP extensions
-spec handle_STARTTLS(#state{}) -> #state{}.
handle_STARTTLS(State) ->
    lager:info("TLS Started"),
    State.

-spec handle_info(Info :: term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: term()}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec code_change(OldVsn :: any(), State :: #state{}, Extra :: any()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec terminate(Reason :: any(), State :: #state{}) -> {'ok', any(), #state{}}.
terminate(Reason, State) ->
    {ok, Reason, State}.

%%% Internal Functions %%%

unique_id() ->
    erlang:unique_integer().

-spec relay(binary(), [binary()], binary()) -> ok.
relay(_, [], _) ->
    ok;
relay(From, [To|Rest], Data) ->
    % relay message to email address
    [_User, Host] = string:tokens(binary_to_list(To), "@"),
    gen_smtp_client:send({From, [To], erlang:binary_to_list(Data)}, [{relay, Host}]),
    relay(From, Rest, Data).
