-record(node, {
          pid :: pid(),
          desc :: iodata(),
          in :: pos_integer(),
          out :: pos_integer(),
          done :: boolean(),
          children :: [#node{}]
         }).
