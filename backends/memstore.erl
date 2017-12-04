-module(memstore).
-export([init/0, create/3, read/2, update/3, delete/2]).

init() -> [].

create(K, V, []) -> [{K, V}];
create(K, V, [{K, _}|T]) -> [{K, V}|T];
create(K, V, [H|T]) -> [H|create(K, V, T)].

read(_, []) -> {error, not_found};
read(K, [{K, V}|_]) -> {ok, V};
read(K, [_|T]) -> read(K, T).

update(K, V, []) -> [{K, V}];
update(K, V, [{K,_}|T]) -> [{K, V}|T];
update(K, V, [H|T]) -> [H|update(K, V, T)].

delete(_, []) -> [];
delete(K, [{K, _}|T]) -> T;
delete(K, [H|T]) -> [H|delete(K, T)].

