// Copyright 2016
// Author: Patrick Brosi

#include "shared/tests/ILPSolverTest.h"
#include "win_compat.h"  // WIN32 PATCH

#include "util/Misc.h"

// _____________________________________________________________________________
int main(int argc, char** argv) {
  win_set_binary_stdio();  // WIN32 PATCH
  UNUSED(argc);
  UNUSED(argv);
  ILPSolverTest gs;

  gs.run();
}
