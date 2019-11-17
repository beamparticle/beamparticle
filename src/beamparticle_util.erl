-module(beamparticle_util).

-export([node_uptime/1]).
-export([trimbin/1,
        bin_to_hex_list/1,
        bin_to_hex_binary/1,
        hex_binary_to_bin/1]).

-export([is_operator/1]).

-export([convert_for_json_encoding/1, encode_for_json/3]).
-export([escape/1, escape_special/1]).

-export([convert_xml_to_json_map/1,
        xml_to_json_map/2]).
-export([convert_to_lower/1,
         convert_first_char_to_lowercase/1]).
-export([del_dir/1]).

-spec node_uptime(millisecond | second) -> integer().
node_uptime(millisecond) ->
    {TotalTimeMsec, _TimeSinceLastCallMsec} = erlang:statistics(wall_clock),
    TotalTimeMsec;
node_uptime(second) ->
    node_uptime(millisecond) div 1000.

%% taken
%% from http://erlang.org/pipermail/erlang-questions/2009-June/044797.html
trimbin(Binary) when is_binary(Binary) ->
    re:replace(Binary, "^\\s+|\\s+$", "", [{return, binary}, global]).

%% @doc Convert a binary to textual representation of the same in hexadecimal
bin_to_hex_binary(X) when is_binary(X) ->
    H = hex_combinations(),
    <<<<(element(V + 1, H)):16>> || <<V:8>> <= X>>.

%% @doc Convert a binary to list representation of the same in hexadecimal
bin_to_hex_list(X) when is_binary(X) ->
    binary_to_list(bin_to_hex_binary(X)).

%% @private
%% @doc Find all possible combinations (sorted) of hexadecimal as a list
%% of integers (ordinal value of hex characters) from 0x00 till 0xff.
hex_combinations() ->
    H = [$0, $1, $2, $3, $4, $5, $6, $7, $8, $9, $a, $b, $c, $d, $e, $f],
    %<< <<((V1 bsl 8) + V2):16>> || V1 <- H, V2 <- H >>.
    list_to_tuple([((V1 bsl 8) + V2) || V1 <- H, V2 <- H]).


%% The following two functions call each other making a recursive loop
%%
%%
%% The following should succeed for any map no matter the nesting.
%%
%% ```
%%   A = #{ <<"a">> => [#{<<"b">> => {1,2,3}}, 1, 2, 3] },
%%   jsx:encode(beamparticle_util:convert_for_json_encoding(A)).
%% ```
%% TODO handle uuid or binaries which are not printable
%% NOTE: tuple are converted to list
-spec convert_for_json_encoding(term()) -> map().
convert_for_json_encoding(Map) when is_map(Map) ->
    maps:fold(fun encode_for_json/3, #{}, Map);
convert_for_json_encoding(V) when is_tuple(V) ->
	convert_for_json_encoding(tuple_to_list(V));
convert_for_json_encoding(V) when is_list(V) ->
	V2 = lists:foldl(fun(E, AccIn) ->
                        [convert_for_json_encoding(E) | AccIn]
                end, [], V),
    lists:reverse(V2);
convert_for_json_encoding(V) ->
    V.

encode_for_json(K, V, AccIn) ->
    AccIn#{K => convert_for_json_encoding(V)}.
%% ------------ end of recursive loop functions --------------

%%--------------------------------------------------------------------
%% @doc
%% convert a hex (in binary format) to binary while assuming that the
%% size of the hex binary must be a multiple of 2, where each
%% byte is represented by two characters.
%% This function uses fun hex_binary_to_bin_internal/2 internally,
%% which throws an exception when the input hex is not a valid
%% but this function catches exception and gives back error.
-spec hex_binary_to_bin(H :: binary()) -> binary() | undefined | error.
hex_binary_to_bin(H) when is_binary(H) andalso (byte_size(H) rem 2 == 0) ->
    %% Note that fun hex_binary_to_bin_internal/2 is tail recursive,
    %% but since that is a different function than the current, so
    %% tail call optimization should still happen even in protected
    %% portion of try..of..catch.
    %% It is important to note that we are not having recursion
    %% to fun hex_binary_to_bin/1 here, which would otherwise
    %% be not tail call optimized (due to need for keeping
    %% reference in case of exception).
    try
        iolist_to_binary(lists:reverse(hex_binary_to_bin_internal(H, [])))
    catch
        error:function_clause -> error
    end;
hex_binary_to_bin(undefined) ->
    undefined;
hex_binary_to_bin(_H) ->
    error.

%% @private
%% @doc
%% convert a hex binary to a binary with the help of an accumulator
%% while this is an internal function to be used by the publically
%% exposed fun hex_binary_to_bin/1.
-spec hex_binary_to_bin_internal(Bin :: binary(), AccIn :: list()) -> list().
hex_binary_to_bin_internal(<<>>, AccIn) ->
    AccIn;
hex_binary_to_bin_internal(<<A:8, B:8, Rest/binary>>, AccIn) ->
    Msb = hex_to_int(A),
    Lsb = hex_to_int(B),
    hex_binary_to_bin_internal(Rest, [(Msb bsl 4) bor (Lsb band 15)] ++ AccIn).

%% @private
%% @doc
%% convert a hex character to integer range [0,15] and
%% throw exception when not a valid hex character.
-spec hex_to_int(V :: byte()) -> 0..15.
hex_to_int(V) when V >= $a andalso V =< $f ->
    V - $a + 10;
hex_to_int(V) when V >= $A andalso V =< $F ->
    V - $A + 10;
hex_to_int(V) when V >= $0 andalso V =< $9 ->
    V - $0.


%% Taken from https://github.com/mojombo/mustache.erl/blob/master/src/mustache.erl
escape(HTML) when is_binary(HTML) ->
  iolist_to_binary(escape(binary_to_list(HTML)));
escape(HTML) when is_list(HTML) ->
  escape(HTML, []).

escape([], Acc) ->
  lists:reverse(Acc);
escape([$< | Rest], Acc) ->
  escape(Rest, lists:reverse("&lt;", Acc));
escape([$> | Rest], Acc) ->
  escape(Rest, lists:reverse("&gt;", Acc));
escape([$& | Rest], Acc) ->
  escape(Rest, lists:reverse("&amp;", Acc));
escape([X | Rest], Acc) ->
  escape(Rest, [X | Acc]).

escape_special(String) ->
    lists:flatten([escape_char(Char) || Char <- String]).

escape_char($\0) -> "\\0";
escape_char($\n) -> "\\n";
escape_char($\t) -> "\\t";
escape_char($\b) -> "\\b";
escape_char($\r) -> "\\r";
escape_char($')  -> "\\'";
escape_char($")  -> "\\\"";
escape_char($\\) -> "\\\\";
escape_char(Char) -> Char.

%% @doc Is the {M,F,A} an Erlang operator?
-spec is_operator({Module :: atom(), F :: atom(), Arity :: integer()}) -> boolean().
is_operator({erlang, F, Arity}) ->
    erl_internal:arith_op(F, Arity) orelse
	erl_internal:bool_op(F, Arity) orelse
	erl_internal:comp_op(F, Arity) orelse
	erl_internal:list_op(F, Arity) orelse
	erl_internal:send_op(F, Arity);
is_operator(_) -> false.

%% @doc Convert XML to json map recursively even within text
%%
%% This function (on best effort basis) tries to convert xml
%% to Erlang map (json serializable), while throwing away the
%% xml attributes. Note that the content within the tags are
%% tried for json decoding and done whenever possible.
%%
%% beamparticle_util:convert_xml_to_json_map(<<"<string>{\"a\": 1}</string>">>).
%% beamparticle_util:convert_xml_to_json_map(<<"<r><string>{\"a\": 1}</string><a>1\n2</a><a>4</a></r>">>).
convert_xml_to_json_map(Content) when is_binary(Content) ->
    case erlsom:simple_form(binary_to_list(Content)) of
        {ok, {XmlNode, _XmlAttribute, XmlValue}, _} ->
            XmlNode2 = case is_list(XmlNode) of
                           true ->
                               unicode:characters_to_binary(XmlNode, utf8);
                           false ->
                               XmlNode
                       end,
            #{XmlNode2 => xml_to_json_map(XmlValue, #{})};
        Error ->
            Error
    end.

xml_to_json_map([], AccIn) ->
    AccIn;
xml_to_json_map([{Node, _Attribute, Value} | Rest], AccIn) ->
    Node2 = case is_list(Node) of
                true ->
                    unicode:characters_to_binary(Node, utf8);
                false ->
                    Node
            end,
    AccIn2 = case maps:get(Node2, AccIn, undefined) of
                 undefined ->
                     AccIn#{Node2 => xml_to_json_map(Value, #{})};
                 OldValue when is_list(OldValue) ->
                     AccIn#{Node2 => [xml_to_json_map(Value, #{}) | OldValue]};
                 OldValue ->
                     AccIn#{Node2 => [xml_to_json_map(Value, #{}), OldValue]}
             end,
    xml_to_json_map(Rest, AccIn2);
xml_to_json_map([V], _AccIn) ->
    case is_list(V) of
        true ->
            try_decode_json(unicode:characters_to_binary(V, utf8));
        false ->
            V
    end;
xml_to_json_map(V, _AccIn) ->
    try_decode_json(V).

%% @doc Convert text to lower case.
%% @todo It do not work for utf8, but only for latin-1
convert_to_lower(Value) when is_binary(Value) ->
    Str = binary_to_list(Value),
    unicode:characters_to_binary(string:to_lower(Str, utf8));
convert_to_lower(Value) when is_list(Value) ->
    string:to_lower(Value).

convert_first_char_to_lowercase(<<H, Rest/binary>> = V) when is_binary(V) ->
    H2 = string:to_lower(H),
    <<H2, Rest/binary>>;
convert_first_char_to_lowercase([H | T] = V) when is_list(V) ->
    H2 = string:to_lower(H),
    [H2] ++ T.

try_decode_json(V) ->
    try
        jiffy:decode(V, [return_maps])
    catch
        _:_ ->
            V
    end.

%% @doc recursively delete folder which may not be empty.
-spec del_dir(Dir :: string()) -> ok.
del_dir(Dir) ->
   lists:foreach(fun(D) ->
                    ok = file:del_dir(D)
                 end, del_all_files([Dir], [])).

del_all_files([], EmptyDirs) ->
   EmptyDirs;
del_all_files([Dir | T], EmptyDirs) ->
   {ok, FilesInDir} = file:list_dir(Dir),
   {Files, Dirs} = lists:foldl(fun(F, {Fs, Ds}) ->
                                  Path = Dir ++ "/" ++ F,
                                  case filelib:is_dir(Path) of
                                     true ->
                                          {Fs, [Path | Ds]};
                                     false ->
                                          {[Path | Fs], Ds}
                                  end
                               end, {[],[]}, FilesInDir),
   lists:foreach(fun(F) ->
                         ok = file:delete(F)
                 end, Files),
   del_all_files(T ++ Dirs, [Dir | EmptyDirs]).
