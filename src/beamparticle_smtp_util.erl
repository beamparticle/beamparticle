%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(beamparticle_smtp_util).

-include("beamparticle_constants.hrl").

-export([raw_send_email/4, save_email_file/2, raw_send_email/6]).
-export([send_plain_email/3, send_email_with_attachment/4]).

%% This is a blocking call.
-spec raw_send_email(FromUsername :: binary(), ToEmail :: binary(), Subject :: binary(), Body :: binary()) -> binary() | {error, atom(), any()} | {error, any()}.
raw_send_email(FromUsername, ToEmail, Subject, Body) ->
    %% PrivDir = code:priv_dir(?APPLICATION_NAME),
    %% {ok, PrivKey} = file:read_file(PrivDir ++ "/ssl/key.pem"),
    SmtpConfig = application:get_env(?APPLICATION_NAME, smtp, []),
    %%DkimSelector = proplists:get_value(dkim_selector, SmtpConfig),
    Domain = proplists:get_value(domain, SmtpConfig),
    %%DKIMOptions = [
    %%    {s, DkimSelector},
    %%    {d, list_to_binary(Domain)},
    %%    {private_key, {pem_plain, PrivKey}}
    %%    %{private_key, {pem_encrypted, EncryptedPrivKey, "password"}}
    %%],
    FromEmail = binary_to_list(FromUsername) ++ "@" ++ Domain,
    FromEmailBin = list_to_binary(FromEmail),
    ToEmailString = binary_to_list(ToEmail),
    SignedMailBody =
    mimemail:encode({<<"text">>, <<"plain">>,
                      [{<<"Subject">>, Subject},
                       {<<"From">>, <<"<", FromEmailBin/binary, ">">>},
                       {<<"To">>, <<"<", ToEmail/binary, ">">>}],
                      [],
                      Body},
                      []),
                      %%[{dkim, DKIMOptions}]),
    %% TODO check - relay to target host directly or should we send to localhost and then send it out as relay?
    [_, TargetHost] = string:tokens(ToEmailString, "@"),
    lager:info("args = ~p", [[{FromEmail, [ToEmailString], SignedMailBody}, [{relay, TargetHost}]]]),
    gen_smtp_client:send({FromEmail, [ToEmailString], SignedMailBody}, [{relay, TargetHost}]).

-spec save_email_file(Data :: binary(), Reference :: string()) -> ok.
save_email_file(Data, Reference) ->
    SmtpConfig = application:get_env(?APPLICATION_NAME, smtp, []),
    MailRoot = proplists:get_value(mail_root, SmtpConfig, "mail"),
    {{Year, Month, _}, _} = calendar:now_to_datetime(),
    File = MailRoot ++ "/" ++ integer_to_list(Year) ++ "/" ++
        integer_to_list(Month) ++ "/" ++ Reference ++ ".eml",
    case filelib:ensure_dir(File) of
        ok ->
            lager:info("Email saved at ~p", [File]),
            file:write_file(File, Data);
        _ ->
            ok
    end.

%% @doc Send email via smtp as a blocking call.
%%
%% ```
%% {FromEmail, ToEmail, Subject, Body, SmtpServer, SmtpPassword} =
%% FromEmail = <<"username@abc.com">>,
%% ToEmail = <<"destination@example.com">>,
%% Subject = <<"hello neeraj">>,
%% Body = <<"hi neeraj\nLet me introduce myself\n">>,
%% SmtpServer = <<"smtp.gmail.com">>,
%% SmtpPassword = <<"Password">>}.
%% beamparticle_smtp_util:raw_send_email(FromEmail, ToEmail, Subject, Body, SmtpServer, SmtpPassword).
%% ```
%%
%% The above returns binary() or
%% ```
%% <<"2.0.0 OK 1511889452 t84sm55737897pfe.160 - gsmtp\r\n">>
%% ```
%%
%% ```
%% Email = {
%%    "username@abc.com",
%%    ["destination@example.com"],
%%    <<"From: Someone <username@abc.com>\r\nTo: Dest <destination@example.com>\r\nSubject: Hello\r\n\r\nit is a test.">>
%%},
%% Options = [
%%    {ssl,true},
%%    {no_mx_lookups,true},
%%    {relay,"smtp.gmail.com"},
%%    {username,"username@abc.com"},
%%    {password,"Password"},
%%    {auth,always},
%%    {trace_fun, fun io:format/2}
%% ],
%% gen_smtp_client:send_blocking(Email, Options).
%% ```
%%
-spec raw_send_email(FromEmail :: binary(), ToEmail :: binary(), Subject :: binary(), Body :: binary(), SmtpServer :: binary(), SmtpPassword :: binary()) -> binary() | {error, atom(), any()} | {error, any()}.
raw_send_email(FromEmail, ToEmail, Subject, Body, SmtpServer, SmtpPassword) ->
    %%PrivDir = code:priv_dir(?APPLICATION_NAME),
    %%{ok, PrivKey} = file:read_file(PrivDir ++ "/ssl/key.pem"),
    %%SmtpConfig = application:get_env(?APPLICATION_NAME, smtp, []),
    %%DkimSelector = proplists:get_value(dkim_selector, SmtpConfig),
    FromEmailString = binary_to_list(FromEmail),
    %%[_, Domain] = string:tokens(FromEmailString, "@"),
    %%DKIMOptions = [
    %%    {s, DkimSelector},
    %%    {d, list_to_binary(Domain)},
    %%    {private_key, {pem_plain, PrivKey}}
    %%    %{private_key, {pem_encrypted, EncryptedPrivKey, "password"}}
    %%],
    ToEmailString = binary_to_list(ToEmail),
    SignedMailBody =
    mimemail:encode({<<"text">>, <<"plain">>,
                      [{<<"Subject">>, Subject},
                       {<<"From">>, <<"<", FromEmail/binary, ">">>},
                       {<<"To">>, <<"<", ToEmail/binary, ">">>}],
                      [],
                      Body},
                      []),
                      %%[{dkim, DKIMOptions}]),
    SmtpServerString = binary_to_list(SmtpServer),
    SmtpPasswordString = binary_to_list(SmtpPassword),
	Email = {FromEmailString, [ToEmailString], SignedMailBody},
	Options = [
		{ssl, true},
		{no_mx_lookups, true},
		{relay, SmtpServerString},
		{username, FromEmailString},
		{password, SmtpPasswordString},
		%%{trace_fun, fun io:format/2},
		{auth, always}
	],
    gen_smtp_client:send_blocking(Email, Options).

%% @doc send out email notification with pre configured smtp credentials.
%% Note that the credentials are taking from the configuration.
%% see sys.config for details.
%% ToEmails must be as follows:
%% ```
%% ToEmails = [<<"Name <someone@example.com>">>, ...]
%% ```
-spec send_plain_email(ToEmails :: [binary()],
                       Subject :: binary(),
                       Body :: binary()) ->
    binary() | {error, atom(), any()} | {error, any()}.
send_plain_email(ToEmails, Subject, Body) ->
    SmtpClientConfig = application:get_env(?APPLICATION_NAME, smtp_client, []),
    FromEmail = proplists:get_value(from_email, SmtpClientConfig),
    SmtpServer = proplists:get_value(relay, SmtpClientConfig),
    SmtpUsername = proplists:get_value(username, SmtpClientConfig),
    SmtpPassword = proplists:get_value(password, SmtpClientConfig),
    Email = beamparticle_smtp_email:mail_plain(FromEmail, ToEmails, Subject, Body, []),
    beamparticle_smtp_email:send_email(Email, SmtpServer, SmtpUsername, SmtpPassword).

%% @doc send out email notification including attachments with pre configured smtp credentials.
%% Note that the credentials are taking from the configuration.
%% see sys.config for details.
%% ToEmails and Attachments must be as follows:
%% ```
%% ToEmails = [<<"Name <someone@example.com>">>, ...],
%% Attachments  = [{<<"someone.jpg">>, <<"image/jpeg">>, JpegImageBin}]
%% ```
%% The MimeType is one of media type in RFC 2822, RFC 2045.
%% see https://en.wikipedia.org/wiki/Media_type.
%%
%% Note that the InlineContentType determines the media type
%% of the Body (argument), which will be sent as inline.
%% In case you want to send an email as HTML then set
%% the Body with html content and ContentType as
%% <<"text/html;charset=utf-8">>.
%%
%% Some sample Media Types are as follows:
%%
%% * application/json
%% * application/xml
%% * application/zip
%% * application/pdf
%% * application/sql
%% * application/ld+json
%% * application/msword (.doc)
%% * application/vnd.openxmlformats-officedocument.wordprocessingml.document(.docx)
%% * application/vnd.ms-excel (.xls)
%% * application/vnd.openxmlformats-officedocument.spreadsheetml.sheet (.xlsx)
%% * application/vnd.ms-powerpoint (.ppt)
%% * application/vnd.openxmlformats-officedocument.presentationml.presentation (.pptx)
%% * audio/mpeg
%% * audio/vorbis
%% * multipart/form-data
%% * text/css
%% * text/html
%% * text/csv
%% * text/plain
%% * image/png
%% * image/jpeg
%% * image/gif
-spec send_email_with_attachment(ToEmails :: [binary()],
                                 Subject :: binary(),
                                 InlineContents :: [{ContentType :: binary(), Body :: binary()}],
                                 Attachments :: [{Name :: binary(),
                                                  MimeType :: binary(),
                                                  Cid :: binary(),
                                                  IsInline :: boolean(),
                                                  Body :: binary()}]) ->
    binary() | {error, atom(), any()} | {error, any()}.
send_email_with_attachment(ToEmails, Subject, InlineContents, Attachments) ->
    SmtpClientConfig = application:get_env(?APPLICATION_NAME, smtp_client, []),
    FromEmail = proplists:get_value(from_email, SmtpClientConfig),
    SmtpServer = proplists:get_value(relay, SmtpClientConfig),
    SmtpUsername = proplists:get_value(username, SmtpClientConfig),
    SmtpPassword = proplists:get_value(password, SmtpClientConfig),
    Email = beamparticle_smtp_email:mail_with_attachments(
              FromEmail, ToEmails, Subject, InlineContents, Attachments),
    beamparticle_smtp_email:send_email(Email, SmtpServer, SmtpUsername, SmtpPassword).

