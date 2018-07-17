%%%-------------------------------------------------------------------
%%% @doc
%%% Serving compressed contents.
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

-module(beamparticle_compress_handler).

-include("beamparticle_constants.hrl").
-include_lib("kernel/include/file.hrl").


-export([init/2]).

init(Req0, Opts) ->
    lager:debug("[~p] ~p received request = ~p, Opts = ~p", [self(), ?MODULE, Req0, Opts]),
	ContentType = content_type(proplists:get_value(type, Opts)),
    FullFilePath = proplists:get_value(file, Opts),
    {ok, FileInfo} = file:read_file_info(FullFilePath),
    ModifiedTime = FileInfo#file_info.mtime,
    CompressedFullFilePath = FullFilePath ++ ".gz",
    case file:read_file_info(CompressedFullFilePath) of
        {error, enoent} ->
            compress_file(FullFilePath);
        {ok, CompressedFileInfo} ->
            CompressedModifiedTime = CompressedFileInfo#file_info.mtime,
            case ModifiedTime > CompressedModifiedTime of
                true ->
                    compress_file(FullFilePath);
                false ->
                    ok
            end
    end,
	{Resp, Req3, Opts2} = send_file_contents(CompressedFullFilePath,
                                             ContentType,
                                             <<"deflate">>,
                                             Req0,
                                             Opts),
    {Resp, Req3, Opts2}.


content_type(js) ->
	<<"application/javascript">>.


%% Send file contents to client via cowboy optimally
-spec send_file_contents(Path :: string(),
                         ContentType :: binary(),
                         ContentEncoding :: binary(),
                         Req :: cowboy_req:req(),
                         State :: term()) ->
    {ok, Req :: cowboy_req:req(), State :: term()}.
send_file_contents(Path, ContentType, ContentEncoding, Req, State) ->
    FileBytes = filelib:file_size(Path),
    case FileBytes of
        Bytes when Bytes > 0 ->
			Req2 = cowboy_req:set_resp_body({sendfile, 0, Bytes, Path}, Req),
            Req3 = cowboy_req:reply(200,
                #{<<"content-type">> => ContentType,
                  <<"content-encoding">> => ContentEncoding}, Req2),
            {ok, Req3, State};
        _ ->
            Req2 = cowboy_req:reply(404,
                #{<<"content-type">> => <<"application/json">>},
                <<"{\"error\": \"content not found\"">>, Req),
            {ok, Req2, State}
    end.

compress_file(FullFilePath) ->
    {ok, Data} = file:read_file(FullFilePath),
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, best_compression),
    CompressedBin = zlib:deflate(Z, Data, finish),
    ok = zlib:deflateEnd(Z),
    zlib:close(Z),
    file:write_file(FullFilePath ++ ".gz", CompressedBin).

