// Copyright 2017
// University of Freiburg - Chair of Algorithms and Datastructures
// Author: Patrick Brosi

#include "util/Misc.h"
#include "win_compat.h"  // WIN32 PATCH

// _____________________________________________________________________________
int main(int argc, char** argv) {
  win_set_binary_stdio();  // WIN32 PATCH
  UNUSED(argc);
  UNUSED(argv);

  return 0;
}
