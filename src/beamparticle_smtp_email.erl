%%% @doc Utilities for email from internet adapted for beamparticle.
%%%
%%% Taken from https://gist.github.com/seriyps/6319602
%%%
%%% Send plaintext email using gen_smtp https://github.com/Vagabond/gen_smtp
%%% This function sends email directly to receiver's SMTP server and don't use MTA relays.
%%%
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
-module(beamparticle_smtp_email).

-export([send_email/1, send_email/4]).
-export([mail_plain/5, mail_with_attachments/5]).


%% derive relay and hostname automatically from Email.
%% Note that relay is to the domain of the first target (to)
-spec send_email(gen_smtp_client:email()) -> binary() | {error, atom(), any()} | {error, any()}.
send_email(Email) ->
    {From, [To | _], _Body} = Email,
    [_, ToDomain] = split_addr(To),
    [_, FromDomain] = split_addr(From),
    Options = [{relay, binary_to_list(ToDomain)},
               {tls, if_availablex},
               {hostname, FromDomain}],
    gen_smtp_client:send_blocking(Email, Options).


-spec send_email(gen_smtp_client:email(), binary(), binary(), binary()) ->
    binary() | {error, atom(), any()} | {error, any()}.
send_email(Email, SmtpServer, SmtpUsername, SmtpPassword) ->
	Options = [
		{ssl, true},
		{no_mx_lookups, true},
		{relay, binary_to_list(SmtpServer)},
		{username, binary_to_list(SmtpUsername)},
		{password, binary_to_list(SmtpPassword)},
		%%{trace_fun, fun io:format/2},
		{auth, always}
	],
    gen_smtp_client:send_blocking(Email, Options).

%% Example plaintext email:
%%
%% ```
%%
%%     Mail = mail_plain(<<"Bob <sender@example.com>">>,
%%                       [<<"Alice <receiver@example.com>">>],
%%                       <<"The mail subject">>, <<"The mail body">>, []),
%%     send_email(Mail).
%%
%% '''
%%
-spec mail_plain(binary(), [binary()], binary(), binary(), Opts) -> gen_smtp_client:email() when
      Opts :: [{headers, [{binary(), binary()}]}].
mail_plain(From, Targets, Subject, Body, Opts) ->
    AddHeaders = proplists:get_value(headers, Opts, []),
    EmailTargets = [{<<"To">>, X} || X <- Targets],
    FixedEmailHeaders = [{<<"From">>, From} | EmailTargets] ++
          [{<<"Subject">>, Subject},
           {<<"Content-Type">>, <<"text/plain; charset=utf-8">>}],
    Mimemail =
        {<<"text">>, <<"plain">>,
         FixedEmailHeaders ++ AddHeaders,
         [{<<"transfer-encoding">>, <<"base64">>}],
         Body},
    FromAddr = extract_addr_rfc822(From),
    ToAddrs = [extract_addr_rfc822(To) || To <- Targets],
    {FromAddr, ToAddrs, mimemail:encode(Mimemail)}.

%% Example email with image attachment:
%%
%% ```
%%   ImgName = "image.jpg",
%%   {ok, ImgBin} = file:read_file(ImgName),
%%   Mail = mail_with_attachments(<<"sender@example.com">>,
%%                                [<<"receiver@example.com">>],
%%                                <<"Photos">>,
%%                                [{<<"text/plain;charset=utf-8">>, <<"See photo in attachment">>}],
%%                                [{ImgName, <<"image/jpeg">>, undefined, false, ImgBin}]),
%%   send_email(Mail).
%%
%% '''
%%
%% A sample email source for inline text, html and images.
%% Note that cid are also referenced within the html content,
%% So the images appear inline.
%% Note that set Cid = undefined when IsInline = false.
%%
%% ```
%% ...
%% Received: by 10.223.163.1 with HTTP; Tue, 28 Nov 2017 22:58:10 -0800 (PST)
%% From: User <user@example.com>
%% Date: Wed, 29 Nov 2017 12:28:10 +0530
%% Message-ID: <CAJ+1rFQHq3wspfSfd1Jn1HA73+W0WKdP+pW+OdWesvJMmQ38qg@mail.gmail.com>
%% Subject: Testing image transfer
%% To: Some <someone.com>
%% Content-Type: multipart/related; boundary="94eb2c0d23f4970f08055f19a8f1"
%%
%% --94eb2c0d23f4970f08055f19a8f1
%% Content-Type: multipart/alternative; boundary="94eb2c0d23f4970f07055f19a8f0"
%%
%% --94eb2c0d23f4970f07055f19a8f0
%% Content-Type: text/plain; charset="UTF-8"
%%
%% Testing image transfer
%%
%% [image: Inline image 1]
%%
%%
%%
%% Can you see this?
%%
%% --94eb2c0d23f4970f07055f19a8f0
%% Content-Type: text/html; charset="UTF-8"
%%
%% <div dir="ltr">Testing image transfer<div><br></div>
%% <div><img src="cid:ii_16006915cacb5f61" alt="Inline image 1" width="273" height="373">
%% <br></div><div><br></div><div><br></div><div><br></div><div>Can you see this?</div></div>
%%
%% --94eb2c0d23f4970f07055f19a8f0--
%% --94eb2c0d23f4970f08055f19a8f1
%% Content-Type: image/png; name="image.png"
%% Content-Disposition: inline; filename="image.png"
%% Content-Transfer-Encoding: base64
%% Content-ID: <ii_16006915cacb5f61>
%% X-Attachment-Id: ii_16006915cacb5f61
%%
%%
%% --94eb2c0d23f4970f08055f19a8f1--
%% '''
-spec mail_with_attachments(
        binary(), [binary()], binary(),
        InlineContents :: [{ContentType :: binary(), Body :: binary()}],
        [{Name :: binary(), MimeType :: binary(), Cid :: binary(), IsInline :: boolean(), Body :: binary()}]) -> gen_smtp_client:email().
mail_with_attachments(From, Targets, Subject, InlineContents, Attachments) ->
    MimeInlines = [begin
                       [Ct1, PotentialCt2] = binary:split(ContentType, <<"/">>),
                       [Ct2 | _] = binary:split(PotentialCt2, <<";">>),
                       {Ct1, Ct2,
                        [{<<"Content-Type">>, ContentType}],
                        [],
                        AtBody}
                   end
                   || {ContentType, AtBody} <- InlineContents],
    MimeAttachments = [begin
                           [Ct1, Ct2] = binary:split(MimeType, <<"/">>),
                           ContentIdHeader = case Cid of
                                                 undefined ->
                                                     [];
                                                 _ ->
                                                     [{<<"Content-ID">>, <<"<", Cid/binary, ">">>},
                                                      {<<"X-Attachment-Id">>, Cid}]
                                             end,
                           Disposition = case IsInline of
                                             false -> <<"attachment">>;
                                             true -> <<"inline">>
                                         end,
                           {Ct1, Ct2,
                            [{<<"Content-Transfer-Encoding">>, <<"base64">>} | ContentIdHeader],
                            [{<<"disposition">>, Disposition},
                             {<<"disposition-params">>,
                              [{<<"filename">>, Name}]}],
                            AtBody}
                       end
                       || {Name, MimeType, Cid, IsInline, AtBody} <- Attachments],
    EmailTargets = [{<<"To">>, X} || X <- Targets],
    FixedEmailHeaders = [{<<"From">>, From} | EmailTargets] ++
          [{<<"Subject">>, Subject}],
    Mimemail = {<<"multipart">>,
               <<"mixed">>,
               FixedEmailHeaders,
               [],
               MimeInlines ++ MimeAttachments},
    FromAddr = extract_addr_rfc822(From),
    ToAddrs = [extract_addr_rfc822(To) || To <- Targets],
    {FromAddr, ToAddrs, mimemail:encode(Mimemail)}.

extract_addr_rfc822(Rfc822) ->
    {ok, [{_, Addr}]} = smtp_util:parse_rfc822_addresses(Rfc822),
    list_to_binary(Addr).

split_addr(MailAddr) ->
    binary:split(MailAddr, <<"@">>).
