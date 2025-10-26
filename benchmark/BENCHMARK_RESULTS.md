================================================================================
DBN.jl COMPREHENSIVE PERFORMANCE COMPARISON
================================================================================


mbo.1m.dbn (53.41 MB)
--------------------------------------------------------------------------------
  Julia read_dbn()               3.00 M/s
  Julia DBNStream()              3.17 M/s
  Julia read_mbo()               17.07 M/s  (optimized)
  Julia write_dbn()              2.38 M/s
  Python databento               10.86 M/s
  Rust dbn CLI                   2.29 M/s

trades.100k.dbn (4.58 MB)
--------------------------------------------------------------------------------
  Julia read_dbn()               0.43 M/s
  Julia DBNStream()              0.44 M/s
  Julia read_trades()            15.06 M/s  (optimized)
  Julia write_dbn()              2.75 M/s
  Python databento               10.05 M/s
  Rust dbn CLI                   1.97 M/s

trades.10m.dbn (457.76 MB)
--------------------------------------------------------------------------------
  Julia read_dbn()               5.55 M/s
  Julia DBNStream()              9.36 M/s
  Julia read_trades()            19.30 M/s  (optimized)
  Python databento               11.25 M/s
  Rust dbn CLI                   2.76 M/s

trades.1m.dbn (45.78 MB)
--------------------------------------------------------------------------------
  Julia read_dbn()               3.10 M/s
  Julia DBNStream()              3.14 M/s
  Julia read_trades()            17.88 M/s  (optimized)
  Julia write_dbn()              2.20 M/s
  Python databento               11.87 M/s
  Rust dbn CLI                   2.67 M/s

================================================================================
Benchmark complete
================================================================================
