# LOOM — Windows Port

> Windows build of [LOOM](https://github.com/ad-freiburg/loom), the transit map 
> generation suite developed by Hannah Bast, Patrick Brosi, and Sabine Storandt 
> at the University of Freiburg. Original tool licensed under GPL-3.0.

This repository contains the Windows compatibility patches that enable LOOM to 
build and run natively on Windows (MSYS2 UCRT64), without Docker or WSL.

**Ported and maintained by [Transport for Cairo](https://transportforcairo.com)**  
A Cairo-based urban mobility consultancy specialising in public transport planning 
and transit technology for cities in the Global South.

## What's different from upstream
All changes are Windows compatibility shims only — no modifications to LOOM's 
core algorithms or data structures. See [PATCHES.md](PATCHES.md) for a full 
registry of every changed file and why.

## Original Authors
- Hannah Bast, Patrick Brosi, Sabine Storandt — University of Freiburg
- Source: https://github.com/ad-freiburg/loom
- Licence: GPL-3.0
