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
-module(dflow_debug).

-behaviour(dflow).

-export([init/2, describe/1, start/2, emit/3, done/2]).

-record(state, {show_data = false,
                start}).


%%--------------------------------------------------------------------
%% @doc Init can be called with one or two arguments, the one argument
%% version will default show_data to <em>false</em>. If <em>true</em>
%% is passed as first argument all data going through the process will
%% be printed using {@link io:format/2}.
%%
%% @spec init(Args :: [term()]) ->
%%   {ok, State :: term(), SubFlow :: dflow:step()}
%%
%% @end
%%--------------------------------------------------------------------

init([ShowData], [_SubF]) ->
    {ok, #state{show_data = ShowData}};

init([], [_SubF]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @doc We simpley describe this module as <em>"debug"</em>.
%%
%% @spec describe(State :: term()) ->
%%   string()
%%
%% @end
%%--------------------------------------------------------------------

describe(_) ->
    "debug".

%%--------------------------------------------------------------------
%% @doc When our {@link start/2} is triggered we store the current
%% time in our state.
%%
%% We also print the payload.
%%
%% @spec start(Payload :: term(), State :: term()) ->
%%   {ok, State}
%%
%% @end
%%--------------------------------------------------------------------

start(Payload, State) ->
    io:format("[~p:0] Started debugger with: ~p.~n", [self(), Payload]),
    {ok, State#state{ start = erlang:system_time(micro_seconds)}}.

%%--------------------------------------------------------------------
%% @doc When our child emits data to us we pass it through. If
%% show_data was set to true we'll also emit the data itself
%% time in our state.
%%
%% For each emit we receive we also print the time difference in ms
%% to the {@link start/2} call.
%%
%%
%% @spec emit(Child :: reference(), Data ::term(), State :: term()) ->
%%   {emit, Data, State}
%%
%% @end
%%--------------------------------------------------------------------

emit(_Child, Data, State = #state{show_data = true, start = Start}) ->
    Diff  = Start - erlang:system_time(micro_seconds),
    io:format("[~p:~p] ~p~n", [self(), Diff, Data]),
    {emit, Data, State};

emit(_Child, Data, State = #state{start = Start}) ->
    Diff  = Start - erlang:system_time(micro_seconds),
    io:format("[~p:~p] data.~n", [self(), Diff]),
    {emit, Data, State}.


%%--------------------------------------------------------------------
%% @doc When our child is done we print the total time taken between
%% {@link start/2} and now in milliseconds and declare ourself done
%% to our parent.
%%
%% We always should have only oen child so we'll always be called with
%% <em>{last, Child}</em>. 
%%
%% @spec done({last, Child :: reference()}, State :: term()) ->
%%   {done, State}
%%
%% @end
%%--------------------------------------------------------------------

done({last, _Child}, State = #state{start = Start}) ->
    Diff  = Start - erlang:system_time(micro_seconds),
    io:format("[~p:~p] Finished.~n", [self(), Diff]),
    {done, State}.
