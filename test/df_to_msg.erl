%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc A dflow step that simply generates the same number over and
%%% over again.
%%%
%%% @end
%%% Created : 14 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(df_to_msg).

-behaviour(dflow).

-export([init/1, describe/1, start/2, emit/3, done/2]).

-record(state, {
          pid :: pid(),
          ref :: reference()
         }).
%%--------------------------------------------------------------------
%% @doc Initializes the constant.
%%
%% @spec init([N :: integer(),
%%             count :: pos_integer()]) ->
%%   {ok, N :: integer(), SubFlow :: []}
%%
%% @end
%%--------------------------------------------------------------------
init([Pid, Ref, Sub]) ->
    {ok, #state{pid = Pid, ref = Ref}, [Sub]}.


%%--------------------------------------------------------------------
%% @doc We simply descrive it as the number it is going to emit.
%%
%% @spec describe(State :: integer()) ->
%%   string()
%%
%% @end
%%--------------------------------------------------------------------

describe(#state{pid = Pid, ref = Ref}) ->
    [pid_to_list(Pid), " ! {emit, ", erlang:ref_to_list(Ref), ", ...}"].

%%--------------------------------------------------------------------
%% @doc The payload passed determines how often the number gets
%% emitted, we simply call <em>start(Count-1)</em> on ourselfs to
%% create a simple loop counting down.
%%
%% @spec start(Payload :: term(), State :: integer()) ->
%%   {ok, State :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

start(_, State)->
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Since we're a leave node we don't have to perform any special
%% action on emit, won't ever get data anyway.
%%
%% @spec emit(Child :: reference(), Data :: term(),
%%            State :: integer()) ->
%%   {ok, N :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

emit(_Child, Data, State = #state{pid = Pid, ref = Ref}) ->
    Pid ! {emit, Ref, Data},
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc We're a leave we should never receive a done.
%%
%% @spec done(Child :: {last, reference()} | reference(),
%%            State :: integer()) ->
%%   {ok, State :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

done(_Child, State = #state{pid = Pid, ref = Ref}) ->
    Pid ! {done, Ref},
    {done, State}.
