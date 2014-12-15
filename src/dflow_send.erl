%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc A dflow step that will send data to a procees using the moral
%%% message (!) instead of following the gen_server cast/call.
%%%
%%% @end
%%% Created : 14 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(dflow_send).

-behaviour(dflow).

-export([init/1, describe/1, start/2, emit/3, done/2]).

-record(state, {
          pass = false :: boolean(),
          pid :: pid(),
          ref :: reference()
         }).
%%--------------------------------------------------------------------
%% @doc Initializes the send step, the <em>Pass</em> argument is
%% optional and defaults to false.
%%
%% If <em>Pass</em> is set to true emits will be handed up further the
%% stream allowing to siphon data without interrupting the flow.
%%
%% If <em>Pass</em> is set to false or not provided this step will
%% act as a 'terminator' and not let any further messages to upstream.
%%
%% @spec init([Pid :: pid(),
%%             Ref :: reference()]) ->
%%             Pass :: boolean()]) ->
%%             Sub :: dflow:step()]) ->
%%   {ok, State :: term(), SubFlow :: []}
%%
%% @end
%%--------------------------------------------------------------------
init([Pid, Ref, Pass, Sub]) ->
    {ok, #state{pid = Pid, ref = Ref, pass = (Pass =:= true)}, [Sub]};

init([Pid, Ref, Sub]) ->
    {ok, #state{pid = Pid, ref = Ref}, [Sub]}.


%%--------------------------------------------------------------------
%% @doc We describe the step as a indea of how the message would look.
%%
%% @spec describe(State :: term()) ->
%%   iodata()
%%
%% @end
%%--------------------------------------------------------------------

describe(#state{pid = Pid, ref = Ref}) ->
    [pid_to_list(Pid), " ! {emit, ", erlang:ref_to_list(Ref), ", ...}"].

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
%% send the message to the requested PID and pass it on to our parent
%% or we just send it and do not let it get furhter upstream.
%%
%% @spec emit(Child :: reference(), Data :: term(),
%%            State :: integer()) ->
%%   {ok, N :: integer()}
%%
%% @end
%%--------------------------------------------------------------------

emit(_Child, Data, State = #state{pid = Pid, ref = Ref, pass = true}) ->
    Pid ! {emit, Ref, Data},
    {emit, Data, State};

emit(_Child, Data, State = #state{pid = Pid, ref = Ref}) ->
    Pid ! {emit, Ref, Data},
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

done(_Child, State = #state{pid = Pid, ref = Ref}) ->
    Pid ! {done, Ref},
    {done, State}.
