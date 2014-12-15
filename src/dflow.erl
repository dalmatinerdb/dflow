%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc
%%%   This is a flow processing library which aims to make it easy to
%%%   write streamed routines for processing data.
%%%
%%%   Each step in the process is handled as a own server allowing them
%%%   to work indipendantly and take advantage of multi core sytems.
%%%
%%%   Most opperations are handled in a asyncronous fashion to prevent
%%%   a slower process from blocking it's children, however to prevent
%%%   unbounded message queue growth the emit changes to syncornous
%%%   mode guaranteeing a maximal queue length of
%%%   (max_q_len) + (num_children).
%%%
%%%   The steps of a flow need to implement the dflow behaviour.
%%%
%%%
%%% The <em>dflow</em> behaviour requires the following callbacks,
%%% please see {@link dflow_debug} and {@link dflow_send} for examples.
%%%
%%% <pre>
%%% init(Args :: [term()]) ->
%%%    {ok, State :: term(), ChildSteps :: child_steps()}.
%%% </pre>
%%%
%%% Called as part of {@link build/2}, must return a initial state
%%% as well as its {@link child_steps()}.
%%%
%%% To simplify matters the child reference can be obmitted or if
%%% only a single item is the child only this item can be returned
%%% without wrapping it in a list.
%%%
%%% When references are provided for child steps the <em>emit</em>
%%% and <em>done</em> events will carry those refs even when a child
%%% links to multiple parents.
%%%
%%% <pre>
%%% describe(State :: term()) ->
%%%    Description :: iodata().
%%% </pre>
%%%
%%% Called as part of {@link describe/1} must return a description of
%%% the step.
%%%
%%% A simple example is just a human readable name but runtime data
%%% can be included.
%%%
%%% <pre>
%%% start(Payload :: term(), State :: term()) ->
%%%    {@link dflow_return()}.
%%% </pre>
%%%
%%% Called as part of {@link start/2}, however child processes only
%%% are triggered when <b>all</b> the parent processses linking
%%% to them are started.
%%%
%%% This is done to guarantee no child is started untill all the
%%% parents it will emit data to are ready.
%%%
%%% However order between different children is not guaranteed!
%%%
%%% <pre>
%%% emit(Child :: reference(), Data :: term(), State :: term()) ->
%%%    {@link dflow_return()}.
%%% </pre>
%%%
%%% A child of the step emitted data, the data and the current state
%%% is passed.
%%%
%%% Erlang guarantees ordered delivery between two processes, so
%%% emits from a single child will arrive in the order they are generatd
%%% however the order amongst children is not guaranteed.
%%%
%%% The <em>Child</em> reference can be used to identify the child.
%%%
%%% <pre>
%%% done(Child :: reference()| {last, Child :: reference()}, State :: term()) ->
%%%    {@link dflow_return()}.
%%% </pre>
%%%
%%% This is called when a child process singals that it's work is done.
%%%
%%% The <em>Child</em> reference can be used to identify the child.
%%%
%%% The DFlow keeps track of the children that are done with their work
%%% and the last <em>done</em> message will have a touple as child in
%%% the form <em>{last, Child :: reference()}</em>. This will signal that
%%% all children now have finished and there will be no more downstream
%%% work.
%%%
%%% The <em>done</em> event does <b>not</b> indicate termination of the
%%% process unless the <em>terminate_when_done</em> option was passed.
%%%
%%% @end
%%% Created : 12 Dec 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(dflow).

-ifdef(TEST).
-ifdef(EQC).
-include_lib("pulse_otp/include/pulse_otp.hrl").
-endif.
-endif.

-behaviour(gen_server).

%% API
-export([
         build/1,
         build/2,
         start/2,
         describe/1,
         desc_to_graphvix/1,
         terminate/1
        ]).

%% Internal API
-export([start_link/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-export_type([step/0, flow_optsions/0]).

-define(SERVER, ?MODULE).
-define(MAX_Q_LEN, 20).

%%--------------------------------------------------------------------
%% @type step() = {Module, Args}
%%   Module = atom(),
%%   Args = [term()].
%%
%% <ul>
%%   <li><em>Module</em> - The module that executes this step, needs
%%       to implement the dflow behaviour</li>
%%   <li><em>Args</em> - A list of arguments passed to the init/1
%%       call to <em>Module</em></li>
%% </ul>
%%
%% Every flow is represented as a step, this steps are then used
%% by eflow to generate a graph of processes with each process
%% representing one step.
%%
%%
%% @end
%%--------------------------------------------------------------------

-type step() :: {Module :: atom(), Args :: [term()]}.


%%--------------------------------------------------------------------
%% @type flow_optsions() = optimize |
%%                         terminate_when_done |
%%                         {max_q_len, MaxQLen}
%%   MaxQLen = pos_integer() | infinity.
%%
%% Configuration options that can be passed to DFlow to control how it
%% builds the process tree or graph.
%%
%% <ul>
%%   <li><em>optimize</em> - When optimize is passed the dflow library
%%       will try to optimize the call graph.</li>
%%   <li><em>terminate_when_done</em> - Will terminate the process after
%%       it signals being done.</li>
%%   <li><em>max_q_len</em> - This decide determine at what point a
%%       step switches from asyncronously passing messages to it's
%%       pareent to syncronously. If set to <em>infinity</em> the
%%       risk exists that the parents message box grows unbounded.<br/>
%%       When set the parents message box will not grow lager then
%%       <em>num_children</em> + <em>max_q_len</em>.</li>
%% </ul>
%%
%% The algorithm is pretty basic. When the tree contains two equal branches,
%% instead of spawing pme processes for each it will just link the top most
%% common process to all parents consuming fro it.
%%
%% A simple example where we have two flow steps:
%% <ul>
%%   <li>+ - adds it's children</li>
%%   <li>N - emits the number N</li>
%% </ul>
%% unoptimized we'd get three processes:
%% <pre>
%%       +
%%      / \
%%     1   1
%% </pre>
%% When optimized DFlow will recognoze that <em>1</em> is used twice and
%% combine those two:
%% <pre>
%%       +
%%      / \
%%      \ /
%%       1
%% </pre>
%%
%% The <em>+</em> process will still receive two numbers however instead
%% of generating them twice they are only generated once.
%%
%% Two branches are considered euqal when both the module and all it's
%% arguments are equal.
%%
%% @end
%%--------------------------------------------------------------------

-type flow_optsions() :: optimize |
                         terminate_when_done |
                         {max_q_len, QLen :: pos_integer() | infinity}.

%%--------------------------------------------------------------------
%% @type step_desc() = {StepPid, Desc, Children}.
%%   StepPid = pid(),
%%   Desc = iodata(),
%%   Children = [step_desc()}.
%%
%% This is used to describe the flow. The <em>StepPid</em> can be used
%% as a unique identifyer for each step. Even when the <em>optimize</em>
%% was passed as a argument during create time the descripion is build
%% fully showing each link!
%%
%% Desc is a human readable string for each step, combined of the
%% description given from the callback module and IO data gathered by
%% DFlow itself.
%%
%% The main purpose of this data is to be passed
%% to {@link desc_to_graphvix/1} however it can be used for other tasks
%% as well.
%%
%% @end
%%--------------------------------------------------------------------

-type step_desc() :: {StepPid :: pid(), Desc :: iodata(),
                      Children :: [step_desc()]}.

%%--------------------------------------------------------------------
%% @type dflow_return() =
%%         {ok, State} |
%%         {emit, Data, State} |
%%         {done, Data, State} |
%%         {done, State}
%%  Data = term(),
%%  State = term().
%%
%% The dflow behaviour callbacks <em>start/2</em>, <em>emit/3</em>,
%% and <em>done/2</em> all return the {@link dflow_return()} type.
%%
%% <em>State</em> in any case will be the state passed to the next
%% invocation of the callback module.
%%
%% Depending on the exact return different actions are taken:
%% <ul>
%%   <li><em>{ok, State}</em> - no additional actions are performed</li>
%%   <li><em>{emit, Data, State}</em> - The <em>Data</em> is emitted
%%       to <b>all</b> parents of this step.</li>
%%   <li><em>{done, Data, State}</em> - The <em>Data</em> is emitted
%%       to <b>all</b> parents of this step. <b>After</b> this <b>all</b>
%%       parents are informed at this step has finished.</li>
%%   <li><em>{done, Data}</em> - <b>All</b> parents are informed at this
%%       step has finished.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------

-type dflow_return() ::
        {ok, State :: term()} |
        {emit, Data :: term(), State :: term()} |
        {done, Data :: term(), State :: term()} |
        {done, State :: term()}.

-type child_step() :: {reference(), step()}.

-type child_steps() ::
        [step()] |
        [child_step()] |
        step() |
        child_step().

-type step_ref() :: {reference(), pid()}.

-callback init(Args :: [term()]) ->
    {ok, State :: term(), ChildSteps :: child_steps()}.

-callback describe(State :: term()) ->
    Description :: iodata().

-callback start(Payload :: term(), State :: term()) ->
    dflow_return().

-callback emit(Child :: reference(), Data :: term(), State :: term()) ->
    dflow_return().

-callback done(Child :: reference()| {last, Child :: reference()},
               State :: term()) ->
    dflow_return().

-record(state, {
          callback_module :: atom(),
          callback_state :: term(),
          parents = [] :: [step_ref()],
          start_count = 0 :: non_neg_integer(),
          parent_count = 1 :: pos_integer(),
          children = [] :: [step_ref()],
          completed_children = [] :: [step_ref()],
          in = 0 :: non_neg_integer(),
          out = 0 :: non_neg_integer(),
          terminate_when_done = false :: boolean(),
          max_q_len = 20 :: pos_integer() | infinity
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc See {@link build/2} with <em>Options</em> set to [optmize].
%%
%% @spec build(Head :: step()) ->
%%   {ok, Ref, Pid}
%%
%% @end
%%--------------------------------------------------------------------

-spec build(Head :: step()) ->
                   {ok, Ref :: reference(), Pid :: pid()}.

build(Head) ->
    build(Head, [optimize]).

%%--------------------------------------------------------------------
%% @doc Builds a flow process tree or graph based the <em>Head</em>
%% and the <em>Options</em> passed. It returns the <em>Ref</em> the
%% calling process should know this process as when dealing with it as
%% a flow child.
%%
%%
%% @spec build(Head :: step(), Options :: [flow_options()]) ->
%%   {ok, Ref :: reference(), Pid :: pid()}
%%
%% @end
%%--------------------------------------------------------------------

-spec build(Head :: step(), Options :: [flow_optsions()]) ->
                   {ok, Ref :: reference(), Pid :: pid()}.

build(Head, Options) ->
    Ref = make_ref(),
    {ok, Pid} = supervisor:start_child(
                  dflow_sup, [{Ref, self()}, Head, dict:new(), Options]),
    receive
        {queries, Ref, _} ->
            ok
    after
        1000 ->
            error(timeout)
    end,
    {ok, Ref, Pid}.

%%--------------------------------------------------------------------
%% @doc Traverses the process tree to give a representation of it's
%% layout including IO counters and other information provided by
%% each process.
%%
%%
%% @spec describe(Head :: pid()) ->
%%   Desc :: step_desc()
%%
%% @end
%%--------------------------------------------------------------------

-spec describe(Head :: pid()) ->
                      Desc :: step_desc().

describe(Head) ->
    gen_server:call(Head, graph, infinity).

%%--------------------------------------------------------------------
%% @doc Translates the output from {@link describe/1} to a graphviz
%% dot file.
%%
%% @spec desc_to_graphvix(Description :: step_desc()) ->
%%   DotData :: iodata()
%%
%% @end
%%--------------------------------------------------------------------

-spec desc_to_graphvix(Description :: step_desc()) ->
                              DotData :: iodata().

desc_to_graphvix(Description) ->
    Edges = lists:usort(flatten(Description, [])),
    ["digraph {\n", [to_gviz(Edge) || Edge <- Edges], "}"].

%%--------------------------------------------------------------------
%% @doc Sends a start signal to the Flow. The start signal is send
%% asyncronous so the order is not guaranteed, however a child will
%% not get the start message until it's it's parents are started and
%% it will get it only once.
%%
%% The <em>Payload</em> passed will be handed to each flow process
%% that is started and stays unmodified throughout the entire call
%% chain.
%%
%% @spec start(Head :: pid(), Payload :: term()) ->
%%   ok
%%
%% @end
%%--------------------------------------------------------------------

-spec start(Head :: pid(), Payload :: term()) ->
                   ok.

start(Head, Payload) ->
    gen_server:cast(Head, {start, Payload}).


%%--------------------------------------------------------------------
%% @doc Terminates a Flow. This can only be called on the <em>Head</em>
%% of the flow, it will terminate the process by using the dflow_sup
%% supervisor and propagate the terminate by the links to the children.
%%
%%
%% @spec terminate(Head :: pid()) ->
%%   ok
%%
%% @end
%%--------------------------------------------------------------------

-spec terminate(Head :: pid()) ->
                   ok.

terminate(Head) ->
    supervisor:terminate_child(dflow_sup, Head).

%%--------------------------------------------------------------------
%% @private
%% @doc Starts the DFlow process.
%%
%% @spec start_link(Parent, Query, Queries, Options) ->
%%   {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Parent, Query, Queries, Opts) ->
    gen_server:start_link(?MODULE, [Parent, Query, Queries, Opts], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([{PRef, Parent}, {Module, Args}, Queries, Opts]) ->
    process_flag(trap_exit, true),
    {ok, CState, SubQs} = Module:init(Args),
    {Queries1, Children} =
        lists:foldl(
          fun ({Ref, Query}, {QAcc, CAcc}) ->
                  case proplists:get_bool(optimize, Opts) of
                      true ->
                          case dict:find(Query, QAcc) of
                              error ->
                                  PSelf = {Ref, self()},
                                  {ok, Pid} = start_link(PSelf, Query, QAcc, Opts),
                                  receive
                                      {queries, Ref, QAcc1} ->
                                          QAcc2 = dict:store(Query, Pid, QAcc1),
                                          {QAcc2, [{Ref, Pid} | CAcc]}
                                  after
                                      1000 ->
                                          error(timeout)
                                  end;
                              {ok, Pid} ->
                                  add_parent(Pid, Ref),
                                  {QAcc, [{Ref, Pid} | CAcc]}
                          end;
                      false ->
                          PSelf = {Ref, self()},
                          {ok, Pid} = start_link(PSelf, Query, QAcc, Opts),
                          receive
                              {queries, Ref, _} ->
                                  {QAcc, [{Ref, Pid} | CAcc]}
                          after
                              1000 ->
                                  error(timeout)
                          end
                  end
          end, {Queries, []}, ensure_refed(SubQs, [])),
    Parent ! {queries, PRef, Queries1},
    QLen = proplists:get_value(max_q_len, Opts, ?MAX_Q_LEN),
    {ok, #state{
            callback_module = Module,
            callback_state = CState,
            max_q_len = QLen,
            terminate_when_done = proplists:get_bool(terminate_when_done, Opts),
            parents = [{PRef, Parent}],
            children = Children
           }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({add_parent, Parent}, _From,
            State = #state{parents = Parents, parent_count = Count}) ->
    {reply, ok, State#state{parents = [Parent | Parents],
                            parent_count = Count + 1}};

handle_call({emit, Ref, Data}, _From,
            State = #state{callback_state = CState,
                           callback_module = Mod}) ->
    CallbackReply = Mod:emit(Ref, Data, CState),
    case handle_callback_reply(CallbackReply, State) of
        {stop, State1} ->
            {stop, normal, State1};
        {ok, State1} ->
            {reply, ok, State1}
    end;

handle_call(graph, _, State = #state{children = Children,
                                     completed_children = Completed,

                                     callback_state = CState,
                                     callback_module = Mod}) ->

    Children1 = [describe(Child) || {_, Child} <- Children ++ Completed],
    Desc = [format_in(State),
            pid_to_list(self()), $\n,
            Mod:describe(CState),
            format_out(State)],
    {reply, {self(), Desc, Children1}, State};

handle_call(terminate, _From, State = #state{}) ->
    {stop, normal, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({start, Payload},
            State = #state{callback_state = CState,
                           children = Children,
                           callback_module = Mod,
                           start_count = SCount,
                           parent_count = PCount}) when PCount =:= SCount + 1 ->
    CallbackReply = Mod:start(Payload, CState),
    [start(Pid, Payload) || {_, Pid} <- Children],
    case handle_callback_reply(CallbackReply, State) of
        {stop, State1} ->
            {stop, normal, State1};
        {ok, State1} ->
            {noreply, State1}
    end;

handle_cast({start, _Payload}, State = #state{start_count = Count}) ->
    {noreply, State#state{start_count = Count + 1}};


handle_cast({emit, Ref, Data},
            State = #state{callback_state = CState,
                           callback_module = Mod, in = In}) ->
    CallbackReply = Mod:emit(Ref, Data, CState),
    case handle_callback_reply(CallbackReply, State#state{in = In + 1}) of
        {stop, State1} ->
            {stop, normal, State1};
        {ok, State1} ->
            {noreply, State1}
    end;

handle_cast({done, Ref}, State = #state{children = Children,
                                        completed_children = Completed,
                                        callback_state = CState,
                                        callback_module = Mod}) ->
    {State1, CRef} = case Children of
                         [{Ref, _} = C] ->
                             {State#state{children = [],
                                          completed_children = [C|Completed]},
                              {last, Ref}};
                         Children ->
                             C = lists:keyfind(Ref, 1, Children),
                             Children1 = lists:keydelete(Ref, 1, Children),
                             {State#state{children = Children1,
                                          completed_children = [C|Completed]},
                              Ref}
                     end,
    CallbackReply = Mod:done(CRef, CState),
    case handle_callback_reply(CallbackReply, State1) of
        {stop, State2} ->
            {stop, normal, State2};
        {ok, State2} ->
            {noreply, State2}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(shutdown, _State) ->
    ok;
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


emit(Parents, Data, QLen) ->
    [emit(Parent, Ref, Data, QLen) || {Ref, Parent} <- Parents].

emit(Pid, Ref, Data, QLen) ->
    case erlang:process_info(Pid, message_queue_len) of
        {message_queue_len, N} when N > QLen ->
            gen_server:call(Pid, {emit, Ref, Data}, infinity);
        _ ->
            gen_server:cast(Pid, {emit, Ref, Data})
    end.

to_gviz({label, From, Label}) ->
    [pid_to_list(From), " [label=\"", Label, "\"];\n"];


%% We swap to and frop because we want arrows pointing from the lower to the
%% higher.
to_gviz({edge, From, To}) ->
    [pid_to_list(To), " -> ", pid_to_list(From), ";\n"].

flatten({Pid, Desc, Children}, Acc) ->
    Acc1 = [{label, Pid, Desc} | Acc],
    lists:foldl(fun ({CPid, CMod, CChildren}, FAcc) ->
                        FAcc1 = [{edge, Pid, CPid} | FAcc],
                        flatten({CPid, CMod, CChildren}, FAcc1)
                end, Acc1, Children).


done(Parents) ->
    [gen_server:cast(Parent, {done, Ref}) ||
        {Ref, Parent} <- Parents].

add_parent(Pid, Ref) ->
    link(Pid),
    gen_server:call(Pid, {add_parent, {Ref, self()}}).


ensure_refed([], Acc) ->
    Acc;
ensure_refed([{Ref, Q} | T], Acc) when is_reference(Ref) ->
    ensure_refed(T, [{Ref, Q} | Acc]);
ensure_refed([Q | T], Acc) ->
    ensure_refed(T, [{make_ref(), Q} | Acc]);
ensure_refed(Q, []) ->
    [{make_ref(), Q}].

handle_callback_reply({ok, CState1}, State) ->
    {ok, State#state{callback_state = CState1}};

handle_callback_reply({emit, Data, CState1},
                      State = #state{parents = Parents, out = Out,
                                     max_q_len = QLen}) ->
    emit(Parents, Data, QLen),
    {ok, State#state{callback_state = CState1, out = Out + 1}};

handle_callback_reply({done, Data, CState1},
                      State = #state{parents = Parents, out = Out,
                                     max_q_len = QLen,
                                     terminate_when_done = false}) ->
    emit(Parents, Data, QLen),
    done(Parents),
    {ok, State#state{callback_state = CState1, out = Out + 1}};

handle_callback_reply({done, Data, CState1},
                      State = #state{parents = Parents, out = Out,
                                     max_q_len = QLen,
                                     terminate_when_done = true}) ->
    emit(Parents, Data, QLen),
    done(Parents),
    {stop, normal, State#state{callback_state = CState1, out = Out + 1}};

handle_callback_reply({done, CState1}, State = #state{parents = Parents}) ->
    done(Parents),
    {ok, State#state{callback_state = CState1}}.

format_in(#state{in = 0}) ->
    "";
format_in(#state{in = V}) ->
    ["[", integer_to_list(V), "]\\nV\\n"].


format_out(#state{out = 0}) ->
    "";
format_out(#state{out = V}) ->
    ["\\n[", integer_to_list(V), "]\\nV"].
