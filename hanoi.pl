:- module(hanoi, [
    initial_towers/2, par/2, stars/3, validate_move/4,
    apply_move/4, solved/1, top_disk/2
]).

% Towers are represented as [A,B,C], each tower is a list with its
% top disk first. Disk 1 is the smallest disk.
% Top-first representation: disk 1 is the first element.
initial_towers(N, [A, [], []]) :-
    integer(N), between(1, 8, N),
    numlist(1, N, A).

par(N, Par) :-
    integer(N), N >= 1,
    Par is (1 << N) - 1.

stars(Moves, Par, Stars) :-
    ( Moves =< Par -> Stars = 3
    ; Moves =< (3 * Par // 2) -> Stars = 2
    ; Stars = 1
    ).

tower_index(a, 1). tower_index(b, 2). tower_index(c, 3).
get_tower(Towers, Name, Tower) :-
    tower_index(Name, I), nth1(I, Towers, Tower).

top_disk(Tower, Disk) :- Tower = [Disk|_].

validate_move(Towers, From, To, Result) :-
    ( From == To -> Result = error(same_tower)
    ; \+ tower_index(From, _) -> Result = error(invalid_source)
    ; \+ tower_index(To, _) -> Result = error(invalid_target)
    ; get_tower(Towers, From, []) -> Result = error(empty_source)
    ; get_tower(Towers, From, [Disk|_]),
      get_tower(Towers, To, Target),
      ( Target = [Top|_], Disk > Top -> Result = error(larger_on_smaller)
      ; Result = ok(Disk)
      )
    ).

apply_move(Towers, From, To, NewTowers) :-
    validate_move(Towers, From, To, ok(Disk)),
    tower_index(From, FI), tower_index(To, TI),
    nth1(FI, Towers, [Disk|Rest]),
    replace_nth1(Towers, FI, Rest, T1),
    nth1(TI, T1, Target),
    replace_nth1(T1, TI, [Disk|Target], NewTowers).

replace_nth1([_|Xs], 1, V, [V|Xs]) :- !.
replace_nth1([X|Xs], N, V, [X|Ys]) :-
    N > 1, N1 is N - 1, replace_nth1(Xs, N1, V, Ys).

solved([[], [], C]) :- C \= [].
