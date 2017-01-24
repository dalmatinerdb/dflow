-record(timing_info, {
          start :: integer(),
          stop :: integer() }).

-record(node, {
          pid :: pid(),
          desc :: iodata(),
          in :: pos_integer(),
          out :: pos_integer(),
          done :: boolean(),
          timing :: #timing_info{},
          children :: [#node{}]
         }).

