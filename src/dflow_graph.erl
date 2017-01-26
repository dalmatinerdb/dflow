-module(dflow_graph).

-include("dflow.hrl").

-export([write_dot/2, desc_to_graphviz/1]).

-export_type([step_desc/0]).

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

-type step_desc() :: #node{}.

%%--------------------------------------------------------------------
%% @doc A helpful wrapper that combines, {@link describe/1},
%% {@link desc_to_graphvix/1} and {@link file:write_file/2} into one
%% simple call.
%%
%% @spec write_dot(File :: file:name_all(), Flow :: pid()) ->
%%                        ok |
%%                        {error, posix() | badarg | terminated |
%%                                system_limit}
%%
%% @end
%%--------------------------------------------------------------------

-spec write_dot(File :: file:name_all(), Flow :: pid()) ->
                       ok |
                       {error, file:posix() | badarg | terminated | system_limit}.

write_dot(File, Flow) ->
    file:write_file(File, desc_to_graphviz(dflow:describe(Flow))).

%%--------------------------------------------------------------------
%% @doc Translates the output from {@link describe/1} to a graphviz
%% dot file format.
%%
%% @spec desc_to_graphviz(Description :: step_desc()) ->
%%   DotData :: iodata()
%%
%% @end
%%--------------------------------------------------------------------

-spec desc_to_graphviz(Description :: step_desc()) ->
                              DotData :: iodata().

desc_to_graphviz(Description) ->
    Edges = lists:usort(flatten(Description, [])),
    ["digraph {\n", [to_gviz(Edge) || Edge <- Edges], "}"].


to_gviz({label, Node}) ->
    [pid_to_list(Node#node.pid), " [label=\"", label(Node), "\"] ",
     "[color=", color(Node), "];\n"];


%% We swap to and from because we want arrows pointing from the lower to the
%% higher.
to_gviz({edge, Parent,
         Child = #node{timing = #timing_info{start = S0, stop = S1}} })
  when S0 =/= undefined andalso S1 =/= undefined ->
    Time =  float_to_list((S1 - S0) / 1000, [{decimals, 4}, compact]),
    [pid_to_list(Child#node.pid), " -> ", pid_to_list(Parent#node.pid),
     " [label=\"", integer_to_list(Child#node.out), " (", Time, "ms) ", "\"] ",
     " [color=", color(Child), "];"];
to_gviz({edge, Parent, Child}) ->
    [pid_to_list(Child#node.pid), " -> ", pid_to_list(Parent#node.pid),
     " [label=\"", integer_to_list(Child#node.out), "\"] ",
     " [color=", color(Child), "];"].

flatten(Parent = #node{children = Children}, Acc) ->
    Acc1 = [{label, Parent} | Acc],
    lists:foldl(fun (Child, FAcc) ->
                        FAcc1 = [{edge, Parent, Child} | FAcc],
                        flatten(Child, FAcc1)
                end, Acc1, Children).

label(#node{desc = Desc, pid = Pid}) ->
    [pid_to_list(Pid), Desc].

%[forat_in(State),
% pid_to_list(self()), $\n, 
% Mod:describe(CState), format_done(State),
% format_out(State)],


color(#node{done = true}) ->
    "black";
color(_) ->
    "red".


%% format_in(#state{in = 0}) ->
%%     "";
%% format_in(#state{in = V}) ->
%%     ["[", integer_to_list(V), "]\\nV\\n"].


%% format_out(#state{out = 0}) ->
%%     "";
%% format_out(#state{out = V}) ->
%%     ["\\n[", integer_to_list(V), "]\\nV"].

%% format_done(#state{completed_children = Done, children = Waiting,
%%                    done = true }) ->
%%     NDone = length(Done),
%%     NTotal = length(Waiting) + NDone,
%%     ["* (", integer_to_list(NDone), "/", integer_to_list(NTotal), ")"];


%% format_done(#state{completed_children = Done, children = Waiting }) ->
%%     NDone = length(Done),
%%     NTotal = length(Waiting) + NDone,
%%     [" (", integer_to_list(NDone), "/", integer_to_list(NTotal), ")"].

