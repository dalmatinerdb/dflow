%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc Example debug dflow. This module will take all data and
%%% threadit through without modification. It allows passing in
%%% a startup option to print the data going through.
%%%
%%% In addition to that it will print the total time between  the
%%% invocation of {@link start/2} and {@link done/2}.
%%%
%%% @end
%%% Created : 14 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(df_arith).

-behaviour(dflow).

-export([init/1, describe/1, start/2, emit/3, done/2]).

-type arith_op() ::  '+' | '-' | '*' | '/'.

-record(state, {
          op :: arith_op(),
          lref :: reference(),
          rref :: reference(),
          left = [] :: [number()],
          right = []:: [number()]
         }).

-type state() :: #state{}.


%%--------------------------------------------------------------------
%% @doc Initializes a arithmetic processos with a given opperation
%% and
%% is passed as first argument all data going through the process will
%% be printed using {@link io:format/2}.
%%
%% @spec init([Left :: dflow:step(),
%%            Op :: arith_op(),
%%            Right :: dflow_oo()]) ->
%%   {ok, State :: state(), SubFlow :: [Left :: dflow:child_step(),
%%                                      Left :: dflow:child_step()]}
%%
%% @end
%%--------------------------------------------------------------------

-spec init([dflow:step() | arith_op()]) ->
                  {ok, State :: state(),
                   SubFlow :: [dflow:child_step()]}.
init([L, Op, R]) when
      Op =:= '+' ;
      Op =:= '-' ;
      Op =:= '*' ;
      Op =:= '/' ->
    LRef = make_ref(),
    RRef = make_ref(),
    {ok, #state{op = Op, lref = LRef, rref = RRef}, [{LRef, L}, {RRef, R}]}.


%%--------------------------------------------------------------------
%% @doc We simpley describe this module as the opperator.
%%
%% @spec describe(State :: state()) ->
%%   string()
%%
%% @end
%%--------------------------------------------------------------------

describe(#state{op = Op}) ->
    atom_to_list(Op).

%%--------------------------------------------------------------------
%% @doc We have no action to perform on a start.
%%
%% @spec start(Payload :: term(), State :: state()) ->
%%   {ok, State :: state()}
%%
%% @end
%%--------------------------------------------------------------------

start(_Payload, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc When our child emits We concatinate it with either the left or
%% right list of data (using the horrible <em>++</em> opperator) to
%% ensure order.
%%
%% Once concatinated we see if both lists are non empty and possibly
%% emit data ourselfs.
%%
%%
%% @spec emit(Child :: reference(), Data :: integer(),
%%            State :: state()) ->
%%   {emit, Data :: integer(), State ::state()}
%%
%% @end
%%--------------------------------------------------------------------

emit(Child, Data, State = #state{lref = Child, left = Left}) ->
    reduce_state(State#state{left = Left ++ [Data]});

emit(Child, Data, State = #state{rref = Child, right = Right}) ->
    reduce_state(State#state{right = Right ++ [Data]}).

%%--------------------------------------------------------------------
%% @doc There is nothing to perform on done. We simply wait for the
%% last child and then claim to be done ourselfs.
%%
%% @spec done({last, Child :: reference()}, State :: state()) ->
%%   {done, State :: state()}
%%
%% @end
%%--------------------------------------------------------------------

done({last, _Child}, State) ->
    {done, State};

done(_, State) ->
    {ok, State}.

reduce_state(State = #state{left = []}) ->
    {ok, State};

reduce_state(State = #state{right = []}) ->
    {ok, State};

reduce_state(State = #state{left = [L | LR],
                            op = '+',
                            right = [R | RR]}) ->
    {emit, L + R, State#state{left = LR, right = RR}};

reduce_state(State = #state{left = [L | LR],
                            op = '-',
                            right = [R | RR]}) ->
    {emit, L - R, State#state{left = LR, right = RR}};

reduce_state(State = #state{left = [L | LR],
                            op = '*',
                            right = [R | RR]}) ->
    {emit, L * R, State#state{left = LR, right = RR}};

reduce_state(State = #state{left = [L | LR],
                            op = '/',
                            right = [R | RR]}) ->
    {emit, L / R, State#state{left = LR, right = RR}}.

