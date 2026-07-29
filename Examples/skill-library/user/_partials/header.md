## {{ dotfolder_name }} Shared Header

A shared, argument-free preamble intended for `{% include "header" %}`
(decision #16, amended by #29). This file lives in `_partials/`, a sibling of
skill directories rather than one itself, so it is invisible to discovery by
construction -- it never gets an id, never appears in a listing, and is only
ever reached through a parent skill's Stencil pass.

Harmless today: the render pipeline (§5) and its `_partials/` include
resolution land at M5. This fixture just proves the stack shape exists ahead
of that work.
