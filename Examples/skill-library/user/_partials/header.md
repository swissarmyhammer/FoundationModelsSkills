## {{ dotfolder_name }} Shared Header

A shared, argument-free preamble intended to be pulled into a skill body via
the Stencil include tag (decision #16, amended by #29). This file lives in
`_partials/`, a sibling of skill directories rather than one itself, so it is
invisible to discovery by construction -- it never gets an id, never appears
in a listing, and is only ever reached through a parent skill's Stencil
pass.

Pass 1 (argument substitution) always runs on the skill body before pass 3
(Stencil) ever loads this file, so a `$`-token written here is never
substituted -- partials stay shared, arg-free building blocks (decision #16).
Literal token follows: $0
