-module(dflow_span).

-export([start_child/2,  stop/0,  tag/2,  log/1, log/2,
         fstart/3, fstop/1, ftag/3, flog/2, id/1]).

start_child(Name, Parent) ->
    case ottersp:get_span() of
        undefined ->
            ottersp:start_child(Name, Parent);
        _ ->
            ok
    end.

stop() ->
    ottersp:finish().

tag(Key, Value) ->
    ottersp:tag(Key, Value, "dflow").

log(Fmt, Args) ->
    log(io_lib:format(Fmt, Args)).

log(Text) ->
    ottersp:log(Text, "dflow").

%% Function style wrappers

id(Span) ->
    case otters:ids(Span) of
        {_TraceID, SpanID} ->
            SpanID;
        undefined ->
            undefined
    end.
fstart(_Module, undefined, _ParentID) ->
    undefined;
fstart(Module, TraceID, ParentID) ->
    otters:start(Module, TraceID, ParentID).

flog(Span, Text) ->
    otters:log(Span, Text, "dflow").

fstop(S) ->
    otters:finish(S).

ftag(S, Key, Value) ->
    otters:tag(S, Key, Value, "dflow").
