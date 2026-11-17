:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).
:- use_module(library(uuid)).
:- use_module(library(lists)).
:- use_module(hanoi).
:- use_module(players).

:- dynamic game/2.
:- http_handler(root(.), http_reply_from_files('public', []), [prefix]).
:- http_handler(root(api/new), api_new, [method(post)]).
:- http_handler(root(api/state), api_state, [method(get)]).
:- http_handler(root(api/move), api_move, [method(post)]).
:- http_handler(root(api/undo), api_undo, [method(post)]).
:- http_handler(root(api/restart), api_restart, [method(post)]).
:- http_handler(root(api/finish), api_finish, [method(post)]).
:- http_handler(root(api/ready), api_ready, [method(post)]).
:- http_handler(root(api/results), api_results, [method(get)]).

start :- http_server(http_dispatch, [port(8080)]),
         format('Pink Hanoi running at http://localhost:8080/~n', []).

run_server :-
    start,
    thread_get_message(_).

:- initialization(run_server, main).


% Game dict fields: id, mode, n, towers, moves, history, status,
% players, basis, current, phase, par.
api_new(Request) :-
    http_read_json_dict(Request, In),
    catch(create_game(In, Out), Error, error_reply(Error, Out)),
    reply_json_dict(Out).

create_game(In, Out) :-
    get_dict(mode, In, Mode0), normalize_atom(Mode0, Mode),
    get_dict(difficulty, In, Difficulty0), normalize_atom(Difficulty0, Difficulty),
    difficulty_disks(Difficulty, N),
    initial_towers(N, Towers), par(N, Par),
    uuid(Id),
    ( Mode == single ->
        get_dict(name, In, Name0), clean_name(Name0, Name),
        Players = [_{name:Name, moves:0, time:0, completed:false}],
        Basis = none, Phase = playing
    ; Mode == multi ->
        get_dict(names, In, Names0),
        maplist(clean_name, Names0, Names),
        length(Names, Count), between(2, 4, Count),
        maplist(new_player, Names, Players),
        get_dict(basis, In, BasisValue), normalize_atom(BasisValue, Basis0),
        ( memberchk(Basis0, [fewest_moves, fastest_time]) -> Basis = Basis0
        ; throw(error(domain_error(competition_basis, Basis0), _)) ),
        Phase = playing
    ; throw(error(domain_error(game_mode, Mode), _))
    ),
    State = _{id:Id, mode:Mode, n:N, towers:Towers, moves:0, history:[],
              status:playing, players:Players, basis:Basis, current:1,
              phase:Phase, par:Par},
    with_mutex(hanoi_state, (retractall(game(Id,_)), assertz(game(Id,State)))),
    state_json(State, Out, true, null).

normalize_atom(X, A) :- atom(X), !, A = X.
normalize_atom(X, A) :- string(X), !, atom_string(A, X).
normalize_id(X, A) :- normalize_atom(X, A).

difficulty_disks(easy, 3).
difficulty_disks(hard, 4).
difficulty_disks(difficult, 5).
difficulty_disks(D, _) :- throw(error(domain_error(difficulty, D), _)).


clean_name(Value, Name) :-
    ( string(Value) ->
        normalize_space(string(N0), Value)
    ; atom(Value) ->
        atom_string(Value, Raw),
        normalize_space(string(N0), Raw)
    ; term_string(Value, Raw),
      normalize_space(string(N0), Raw)
    ),
    ( N0 == "" ->
        Name = "Player"
    ;
        string_length(N0, Length),
        Take is min(Length, 24),
        sub_string(N0, 0, Take, _, Name)
    ).

new_player(Name, _{name:Name, moves:0, time:0, completed:false}).

api_state(Request) :-
    http_parameters(Request, [id(Id0, [string])]), normalize_id(Id0, Id),
    ( game(Id, State) -> state_json(State, Out, true, null)
    ; Out = _{valid:false, error:"unknown_game", finished:false}
    ),
    reply_json_dict(Out).

api_move(Request) :-
    http_read_json_dict(Request, In),
    get_dict(id, In, Id0), normalize_id(Id0, Id), get_dict(from, In, From), get_dict(to, In, To),
    with_mutex(hanoi_state,
      ( game(Id, S0) ->
          move_state(S0, From, To, S1, Valid, Error),
          retract(game(Id,S0)), assertz(game(Id,S1)),
          state_json(S1, Out0, Valid, Error)
      ; Out0 = _{valid:false,error:"unknown_game",finished:false}
      )),
    reply_json_dict(Out0).

move_state(S, _, _, S, false, game_not_active) :-
    ( get_dict(status,S,Status), Status \= playing
    ; get_dict(phase,S,Phase), Phase \= playing
    ), !.
move_state(S0, From0, To0, S1, Valid, Error) :-
    normalize_tower(From0, From), normalize_tower(To0, To),
    get_dict(towers,S0,Towers),
    ( validate_move(Towers,From,To,ok(_)) ->
        apply_move(Towers,From,To,NewTowers),
        get_dict(moves,S0,M0), M is M0+1,
        get_dict(history,S0,H0),
        H = [_{from:From,to:To}|H0],
        put_dict(_{towers:NewTowers,moves:M,history:H},S0,Sx),
        ( solved(NewTowers) -> put_dict(status,Sx,solved,S1)
        ; S1=Sx ),
        Valid=true, Error=null
    ; validate_move(Towers,From,To,error(Reason)),
      S1=S0, Valid=false, Error=Reason
    ).

normalize_tower(X, X) :- atom(X), !.
normalize_tower(X, A) :- string(X), atom_string(A,X).
api_undo(Request) :-
    http_read_json_dict(Request, In), get_dict(id,In,Id0), normalize_id(Id0,Id),
    with_mutex(hanoi_state,
      ( game(Id,S0) ->
          ( get_dict(mode,S0,single), get_dict(status,S0,playing),
            get_dict(history,S0,[H|Rest]) ->
              get_dict(from,H,From), get_dict(to,H,To),
              get_dict(towers,S0,T0),
              apply_move(T0,To,From,T1),
              get_dict(moves,S0,M0), M is max(0,M0-1),
              put_dict(_{towers:T1,moves:M,history:Rest},S0,S1),
              retract(game(Id,S0)),assertz(game(Id,S1)),
              state_json(S1,Out,true,null)
          ; Out=_{valid:false,error:"undo_unavailable",finished:false}
          )
      ; Out=_{valid:false,error:"unknown_game",finished:false}
      )),
    reply_json_dict(Out).

api_restart(Request) :-
    http_read_json_dict(Request,In), get_dict(id,In,Id0), normalize_id(Id0,Id),
    with_mutex(hanoi_state,
      ( game(Id,S0) ->
          ( get_dict(mode,S0,single) ->
              get_dict(n,S0,N), initial_towers(N,T),
              put_dict(_{towers:T,moves:0,history:[],status:playing,phase:playing},S0,S1),
              retract(game(Id,S0)),assertz(game(Id,S1)),
              state_json(S1,Out,true,null)
          ; Out=_{valid:false,error:"restart_unavailable",finished:false}
          )
      ; Out=_{valid:false,error:"unknown_game",finished:false}
      )),
    reply_json_dict(Out).

api_finish(Request) :-
    http_read_json_dict(Request,In), get_dict(id,In,Id0), normalize_id(Id0,Id), get_dict(time,In,Time0),
    Time is max(0, round(Time0)),
    with_mutex(hanoi_state,
      ( game(Id,S0) ->
          finish_state(S0,Time,S1,Out),
          retract(game(Id,S0)),assertz(game(Id,S1))
      ; Out=_{valid:false,error:"unknown_game",finished:false}
      )),
    reply_json_dict(Out).

finish_state(S0, Time, S1, Out) :-
    get_dict(status,S0,solved),
    get_dict(mode,S0,Mode),
    ( Mode == single ->
        get_dict(players,S0,[P0]), get_dict(moves,S0,M),
        put_dict(_{moves:M,time:Time,completed:true},P0,P1),
        put_dict(players,S0,[P1],S1),
        get_dict(par,S0,Par), stars(M,Par,Stars),
        state_json(S1,Base,true,null),
        put_dict(_{finished:true,completion_time:Time,stars:Stars},Base,Out)
    ; get_dict(players,S0,Ps0), get_dict(current,S0,I),
      nth1(I,Ps0,P0), get_dict(moves,S0,M),
      put_dict(_{moves:M,time:Time,completed:true},P0,P1),
      replace_player(Ps0,I,P1,Ps1),
      length(Ps1,Total),
      ( I < Total ->
          Next is I+1,
          put_dict(_{players:Ps1,current:Next,phase:handoff,towers:[],moves:0,history:[],status:playing},S0,S1),
          state_json(S1,Base,true,null), put_dict(_{finished:false,phase:handoff},Base,Out)
      ; put_dict(_{players:Ps1,phase:results},S0,S1),
        state_json(S1,Base,true,null), put_dict(_{finished:true,phase:results},Base,Out)
      )
    ).

replace_player([_|Xs],1,P,[P|Xs]) :- !.
replace_player([X|Xs],N,P,[X|Ys]) :- N>1,N1 is N-1,replace_player(Xs,N1,P,Ys).

api_ready(Request) :-
    http_read_json_dict(Request,In), get_dict(id,In,Id0), normalize_id(Id0,Id),
    with_mutex(hanoi_state,
      ( game(Id,S0) ->
          ( get_dict(mode,S0,multi), get_dict(phase,S0,handoff) ->
              get_dict(n,S0,N),initial_towers(N,T),
              put_dict(_{towers:T,moves:0,history:[],status:playing,phase:playing},S0,S1),
              retract(game(Id,S0)),assertz(game(Id,S1)),
              state_json(S1,Out,true,null)
          ; Out=_{valid:false,error:"not_waiting_for_ready",finished:false}
          )
      ; Out=_{valid:false,error:"unknown_game",finished:false}
      )),
    reply_json_dict(Out).

api_results(Request) :-
    http_parameters(Request,[id(Id0,[string])]), normalize_id(Id0,Id),
    ( game(Id,S), get_dict(mode,S,multi), get_dict(phase,S,results) ->
        get_dict(basis,S,Basis),get_dict(players,S,Ps),
        rank_players(Basis,Ps,Ranked), winners(Basis,Ps,WinPs),
        maplist(player_name,WinPs,WinnerNames),
        Out=_{valid:true,finished:true,basis:Basis,ranking:Ranked,winners:WinnerNames}
    ; Out=_{valid:false,error:"results_not_available",finished:false}
    ),
    reply_json_dict(Out).

player_name(P,N) :- get_dict(name,P,N).

state_json(S, Out, Valid, Error) :-
    get_dict(towers,S,T), get_dict(moves,S,M), get_dict(par,S,Par),
    get_dict(status,S,Status), get_dict(mode,S,Mode), get_dict(n,S,N),
    get_dict(current,S,I), get_dict(players,S,Players), get_dict(phase,S,Phase),
    ( nth1(I,Players,P) -> get_dict(name,P,Name) ; Name = "" ),
    ( Status == solved -> Finished=true ; Finished=false ),
    get_dict(id,S,Id),
    Out=_{id:Id,valid:Valid,error:Error,towers:T,moves:M,par:Par,status:Status,
          finished:Finished,mode:Mode,disks:N,current_player:Name,
          current_player_index:I,phase:Phase}.

error_reply(Error, Out) :-
    message_to_string(Error, Message),
    Out=_{valid:false,error:Message,finished:false}.
