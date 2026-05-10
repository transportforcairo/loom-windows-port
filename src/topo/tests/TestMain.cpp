// Copyright 2016
// Author: Patrick Brosi

#include "topo/tests/ContractTest.h"
#include "win_compat.h"  // WIN32 PATCH
#include "topo/tests/ContractTest2.h"
#include "topo/tests/TopologicalTest.h"
#include "topo/tests/RestrInfTest.h"

#include "util/Misc.h"

// _____________________________________________________________________________
int main(int argc, char** argv) {
  win_set_binary_stdio();  // WIN32 PATCH
  UNUSED(argc);
  UNUSED(argv);
  ContractTest2 ct2;
  ContractTest ct;
  TopologicalTest tt;
  RestrInfTest rt;

  rt.run();
  ct2.run();
  ct.run();
  tt.run();
}
