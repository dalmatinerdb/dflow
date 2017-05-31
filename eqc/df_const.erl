%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc A dflow step that simply generates the same number over and
%%% over again.
%%%
%%% @end
%%% Created : 14 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(df_const).

-behaviour(dflow).

-export([init/2, describe/1, start/2, emit/3, done/2]).

%%--------------------------------------------------------------------
%% @doc Initializes the constant.
%%
%% @spec init([N :: integer(),
%%             count :: pos_integer()]) ->
%%   {ok, N :: integer(), SubFlow :: []}
%%
%% @end
%%--------------------------------------------------------------------

-spec init([integer()], []) ->
                  {ok, State :: integer()}.
init([N], []) ->
    {ok, N}.


%%--------------------------------------------------------------------
%% @doc We simply descrive it as the number it is going to emit.
%%
%% @spec describe(State :: integer()) ->
%%   string()
%%
%% @end
%%--------------------------------------------------------------------

describe(N) ->
    integer_to_list(N).

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

start(1, N) ->
    {done, N, N};

start(_Count, N)  when _Count < 1->
    {done, N};

start(Count, N) ->
    dflow:start(self(), Count - 1),
    {emit, N, N}.

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

emit(_, _, N) ->
    {ok, N}.

%%--------------------------------------------------------------------
%% @doc We're a leave we should never receive a done.
%%
%% @spec done(Child :: {last, reference()} | reference(),
%%            State :: integer()) ->
%%   {ok, State :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

done(_, N) ->
    {ok, N}.
