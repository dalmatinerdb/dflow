%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc A dflow step that will send data to a procees using the moral
%%% message (!) instead of following the gen_server cast/call.
%%%
%%% @end
%%% Created : 14 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(dflow_apply).

-behaviour(dflow).

-export([init/2, describe/1, start/2, emit/3, done/2]).

-record(state, {
          pass = false :: boolean(),
          func :: function()
         }).
%%--------------------------------------------------------------------
%% @doc Initializes the send step, the <em>Pass</em> argument is
%% optional and defaults to false.
%%
%% If <em>Pass</em> is set to true, emits will be handed up further the
%% stream allowing to siphon data without interrupting the flow.
%%
%% If <em>Pass</em> is set to false or not provided this step will
%% act as a 'terminator' and not let any further messages to upstream.
%%
%% @spec init([Fun :: function(),
%%             Pass :: boolean()]) ->
%%             Sub :: dflow:step()]) ->
%%   {ok, State :: term(), SubFlow :: []}
%%
%% @end
%%--------------------------------------------------------------------
init([Fun, Pass], [_Sub]) ->
    {ok, #state{func = Fun, pass = (Pass =:= true)}};

init([Fun], [_Sub]) ->
    {ok, #state{func = Fun}}.


%%--------------------------------------------------------------------
%% @doc We describe the step as the function passed.
%%
%% @spec describe(State :: term()) ->
%%   iodata()
%%
%% @end
%%--------------------------------------------------------------------

describe(#state{func = Fun}) ->
    [erlang:fun_to_list(Fun), "(Data)"].

%%--------------------------------------------------------------------
%% @doc There is no need to emit start.
%%
%% @spec start(Payload :: term(), State :: term()) ->
%%   {ok, State :: term()}
%%
%% @end
%%--------------------------------------------------------------------

start(_, State)->
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Depending if <em>pass</em> is set to true or not we either
%% invoke the provided function and pass it on to our parent  or we
%% just invoce the function and do not let it get furhter upstream.
%%
%% @spec emit(Child :: reference(), Data :: term(),
%%            State :: term()) ->
%%   {ok, State :: term()}
%%
%% @end
%%--------------------------------------------------------------------

emit(_Child, Data, State = #state{func = Fun, pass = true}) ->
    Fun(Data),
    {emit, Data, State};

emit(_Child, Data, State = #state{func = Fun}) ->
    Fun(Data),
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc No mater if <em>pass</em> was set we send the done message to
%% both our parent and the requested process.
%%
%% @spec done(Child :: {last, reference()} | reference(),
%%            State :: integer()) ->
%%   {ok, State :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

done(_Child, State = #state{func = Fun}) ->
    Fun(done),
    {done, State}.
