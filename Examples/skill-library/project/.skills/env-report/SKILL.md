---
name: env-report
description: Reports HOME and the working directory through the Stencil precedence ladder, and includes the shared header partial.
---

{% include "header" %}

HOME={{ HOME }}
WORKING_DIRECTORY={{ working_directory }}
