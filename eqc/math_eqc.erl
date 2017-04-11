%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created : 15 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>

-module(math_eqc).

-include_lib("eqc/include/eqc.hrl").
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


setup() ->
    {ok, _} = application:ensure_all_started(dflow),
    otters_config:write(zipkin_collector_uri, "http://127.0.0.1:9411/api/v1/spans"),
    otters_config:write(filter_rules, [{[], [send_to_zipkin]}]),
    fun () ->
            ok
    end.

prop_matches() ->
    ?SETUP(fun setup/0,
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
                 end))).


prop_optimized() ->
    ?SETUP(fun setup/0,
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
                 end))).

run_and_collect(Eq, N, Opts) ->
    TID = otters_lib:id(),
    Sp0 = otters:start(eqc, TID),
    Sp1 = otters:tag(Sp0, service, qec, "eqc"),
    Opts1 = [{trace_id, TID} | Opts],
    Ref = make_ref(),
    {ok, _, Flow} = dflow:build({dflow_send, [self(), Ref, Eq]}, Opts1),
    Sp2 = otters:log(Sp1, "build", "eqc"),
    ok = dflow_graph:write_dot("./current.dot", Flow),
    Sp3 = otters:log(Sp2, "write dot", "eqc"),
    dflow:start(Flow, N),
    Sp4 = otters:log(Sp3, "start", "eqc"),
    {ok, Replies} = dflow_send:recv(Ref),
    Sp5 = otters:log(Sp4, "recv", "eqc"),
    ok = dflow_graph:write_dot("./current.dot", Flow),
    Sp6 = otters:log(Sp5, "write new dot", "eqc"),
    dflow:terminate(Flow),
    Sp7 = otters:log(Sp6, "terminate", "eqc"),
    [Result] = lists:usort(Replies),
    otters:finish(Sp7),
    {Result, length(Replies)}.

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
