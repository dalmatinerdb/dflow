-module(dflow_span).

-export([id/1, start/2, stop/0, tag/2, log/1,
        fstart/2, flog/2]).

-define(IF_SPAN(Code),
        case otter:span_pget() of
            undefined ->
                ok;
            _ ->
                Code
        end).

%% Random 64 bit integer.
id(undefined) ->
    undefined;

id(_ParentSpan) ->
    otter_lib:id().

start(_, undefined) ->
    ok;
start(Name, TraceID) ->
    otter:span_pstart(Name, TraceID).

stop() ->
    ?IF_SPAN(otter:span_pend()).

tag(Key, Value) ->
    ?IF_SPAN(otter:span_ptag(Key, Value, "dflow")).

log(Text) ->
    ?IF_SPAN(otter:span_plog(Text, "dflow")).

%% Function style wrappers

fstart(_Module, undefined) ->
    undefined;

fstart(Module, TraceID) ->
    otter:span_start(Module, TraceID).

flog(undefined, _) ->
    undefined;

flog(Span, Text) ->
    otter:span_log(Span, Text, "dflow").
