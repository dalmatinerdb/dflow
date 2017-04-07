-module(dflow_span).

-export([start/2,  stop/0,  tag/2,  log/1, log/2,
         fstart/2, fstop/1, ftag/3, flog/2]).

start(_, undefined) ->
    ok;
start(Name, TraceID) ->
    case ottersp:get_span() of
        undefined ->
            ottersp:start(Name, TraceID);
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

fstart(Module, TraceID) ->
    otters:start(Module, TraceID).

flog(Span, Text) ->
    otters:log(Span, Text, "dflow").

fstop(S) ->
    otters:finish(S).

ftag(S, Key, Value) ->
    otters:tag(S, Key, Value, "dflow").
