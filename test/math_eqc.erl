%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created : 15 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>

-module(math_eqc).

-ifdef(TEST).
-ifdef(EQC).

-include_lib("fqc/include/fqc.hrl").
-include_lib("pulse/include/pulse.hrl").
-include_lib("pulse_otp/include/pulse_otp.hrl").

-compile(export_all).

-define(TREE_DEPTH, 7).



%% We don't use divide since handeling the division by zery would be
%% too much pain!
op() ->
    oneof(['+', '-', '*']).

runs() ->
    ?SUCHTHAT(N, int(), N > 0).

equasion() ->
    ?SIZED(Size, equasion(Size)).


equasion(Size) ->
    ?LAZY(oneof(
            [{df_const, [int()]} || Size == 0]
            ++ [?LETSHRINK(
                   [L, R], [equasion(Size - 1), equasion(Size - 1)],
                   {df_arith, [L, op(), R]}) || Size > 0])).


prop_matches() ->
    ?FORALL(
       Size, choose(1, ?TREE_DEPTH),
       ?FORALL(
          {Eq, N}, {resize(Size, equasion()), runs()},
          begin
              Calculated = calculate(Eq),
              ?PULSE(
                 Result, run_and_collect(Eq, N, []),
                 ?WHENFAIL(
                    io:format(user, "Eq: ~s~n~p =/= ~p~n",
                              [prettify(Eq), Calculated, Result]),
                    {Calculated, N} =:= Result))
          end)).


prop_optimized() ->
    ?FORALL(
       Size, choose(1, ?TREE_DEPTH),
       ?FORALL(
          {Eq, N}, {resize(Size, equasion()), runs()},
          begin
              Calculated = calculate(Eq),
              ?PULSE(
                 Result, run_and_collect(Eq, N, [optimize]),
                 ?WHENFAIL(
                    io:format(user, "Eq: ~s~n~p =/= ~p~n",
                              [prettify(Eq), Calculated, Result]),
                    {Calculated, N} =:= Result))
          end)).

run_and_collect(Eq, N, Opts) ->
    application:start(dflow),
    Ref = make_ref(),
    {ok, _, Flow} = dflow:build({df_to_msg, [self(), Ref, Eq]}, Opts),
    ok = file:write_file("./current.dot", dflow:desc_to_graphvix(
                                            dflow:describe(Flow))),
    dflow:start(Flow, N),
    {ok, Replies} = collect_replies(Ref, []),
    dflow:terminate(Flow),
    [Result] = lists:usort(Replies),
    {Result, length(Replies)}.


collect_replies(Ref, Acc) ->
    receive
        {emit, Ref, Data} ->
            collect_replies(Ref, [Data | Acc]);
        {done, Ref} ->
            {ok, lists:reverse(Acc)}
    after
        5000 ->
            {error, timeout}
    end.

calculate({dflow_debug, [_, C]}) ->
    calculate(C);

calculate({df_const, [N]}) ->
    N;
calculate({df_arith, [L, '+', R]}) ->
    calculate(L) + calculate(R);

calculate({df_arith, [L, '-', R]}) ->
    calculate(L) - calculate(R);

calculate({df_arith, [L, '*', R]}) ->
    calculate(L) * calculate(R).

prettify({dflow_debug, [_, C]}) ->
    prettify(C);
prettify({df_const, [N]}) ->
    integer_to_list(N);
prettify({df_arith, [L, '+', R]}) ->
    [$(, prettify(L),  " + ", prettify(R), $)];

prettify({df_arith, [L, '-', R]}) ->
    [$(, prettify(L),  " - ", prettify(R), $)];

prettify({df_arith, [L, '*', R]}) ->
    [$(, prettify(L),  " * ", prettify(R), $)].

-endif.
-endif.
