:- module(players, [rank_players/3, winners/2]).

% Each player is a dict with name, moves, time, completed.
% Incomplete players are excluded from the final ranking.
rank_players(Basis, Players, Ranked) :-
    include(completed_player, Players, Done),
    predsort(compare_player(Basis), Done, Sorted),
    assign_ranks(Sorted, 1, Ranked).

completed_player(P) :- get_dict(completed, P, true).

compare_player(fewest_moves, A, B, Order) :-
    get_dict(moves, A, AM), get_dict(moves, B, BM),
    get_dict(time, A, AT), get_dict(time, B, BT),
    compare_pair(AM-AT, BM-BT, Order0), tie_name_order(Order0, A, B, Order).
compare_player(fastest_time, A, B, Order) :-
    get_dict(time, A, AT), get_dict(time, B, BT),
    get_dict(moves, A, AM), get_dict(moves, B, BM),
    compare_pair(AT-AM, BT-BM, Order0), tie_name_order(Order0, A, B, Order).

tie_name_order((=), A, B, Order) :- !, get_dict(name,A,AN), get_dict(name,B,BN), compare(Order,AN,BN).
tie_name_order(Order, _, _, Order).

compare_pair(A1-A2, B1-B2, Order) :-
    ( A1 < B1 -> Order = (<)
    ; A1 > B1 -> Order = (>)
    ; A2 < B2 -> Order = (<)
    ; A2 > B2 -> Order = (>)
    ; Order = (=)
    ).

assign_ranks([], _, []).
assign_ranks([P|Ps], Rank, [R|Rs]) :-
    put_dict(rank, P, Rank, R),
    Next is Rank + 1,
    assign_ranks(Ps, Next, Rs).

winners(Basis, Players) :-
    rank_players(Basis, Players, [Best|_]),
    get_dict(moves, Best, BM), get_dict(time, Best, BT),
    include(same_score(Basis, BM, BT), Players, Winners),
    Winners \= [].

same_score(fewest_moves, M, T, P) :-
    get_dict(completed, P, true), get_dict(moves, P, M), get_dict(time, P, T).
same_score(fastest_time, M, T, P) :-
    get_dict(completed, P, true), get_dict(moves, P, M), get_dict(time, P, T).
