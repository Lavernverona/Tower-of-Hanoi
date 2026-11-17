:- begin_tests(hanoi).
:- use_module('../hanoi').
test(par_easy) :- par(3,7).
test(par_hard) :- par(4,15).
test(par_difficult) :- par(5,31).
test(initial) :- initial_towers(3, [[1,2,3],[],[]]).
test(empty_source) :- validate_move([[1],[],[]], b, c, error(empty_source)).
test(same_tower) :- validate_move([[1],[],[]], a, a, error(same_tower)).
test(larger_on_smaller) :- validate_move([[2],[1],[]], a, b, error(larger_on_smaller)).
test(legal_move) :- validate_move([[1],[],[]], a, b, ok(1)).
test(apply_move) :- apply_move([[1,2],[],[]],a,b,[[2],[1],[]]).
test(stars_3) :- stars(7,7,3).
test(stars_2_low) :- stars(8,7,2).
test(stars_2_high) :- stars(10,7,2).
test(stars_1) :- stars(11,7,1).
:- end_tests(hanoi).
