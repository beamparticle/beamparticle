-module(beamparticle_util).

-export([node_uptime/1]).
-export([trimbin/1,
        bin_to_hex_list/1,
        bin_to_hex_binary/1,
        hex_binary_to_bin/1]).

-export([convert_for_json_encoding/1, encode_for_json/3]).
-export([escape/1, escape_special/1]).


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
        list_to_binary(lists:reverse(hex_binary_to_bin_internal(H, [])))
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
