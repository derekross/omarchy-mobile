<!-- SPDX-License-Identifier: MIT -->
# Review lessons

What reviewing pull requests on Omarchy Mobile has taught us, one lesson
per entry: the rule, why it matters, how to check it, and the review it came
from. The lessons themselves are in [`lessons/`](lessons/), one file per area,
each small enough to read in one go. The reviewer agent
(`.claude/agents/omamobile-reviewer.md`) reads the files that apply before
every review, and a human reviewer can use them as a checklist.

**How it grows.** Each review ends with candidate lessons: a pattern that
caught a real problem, or a mistake the review made. The maintainer confirms
or corrects them, and confirmed ones are added here in the same commit as
the change that prompted them (`docs/review: …`). A lesson that turns out
wrong is corrected in place, with the date and why, never silently deleted:
the corrections are lessons too. Keep entries short; link the evidence.

Entries are grouped by area. `L-<n>` and `C-<n>` numbers never change, so
reviews can cite them, and each number is in exactly one file
(`grep -rn 'L-123\.' docs/review/lessons` finds it).

## The files

| Area | Files | Entries | Read for |
| --- | --- | --- | --- |
| Safety model (AGENTS.md section 1) | [`safety.md`](lessons/safety.md), [`safety-2.md`](lessons/safety-2.md) | 78 | every review |
| Shared code and the reference device | [`shared-code.md`](lessons/shared-code.md), [`shared-code-2.md`](lessons/shared-code-2.md) | 78 | omarchy-mobile and app pull requests |
| Shell and scripts | [`shell.md`](lessons/shell.md) | 56 | omarchy-mobile and app pull requests |
| Kernel (linux-omarchy-mobile) | [`kernel.md`](lessons/kernel.md), [`kernel-2.md`](lessons/kernel-2.md) | 119 | linux-omarchy-mobile pull requests |
| The gates themselves | [`gates.md`](lessons/gates.md), [`gates-2.md`](lessons/gates-2.md) | 76 | every review |
| Reviews and merging | [`reviews.md`](lessons/reviews.md), [`reviews-2.md`](lessons/reviews-2.md) | 94 | every review |
| Claims and evidence | [`claims.md`](lessons/claims.md), [`claims-2.md`](lessons/claims-2.md), [`claims-3.md`](lessons/claims-3.md) | 156 | every review |
| Corrections (where a review was wrong) | [`corrections.md`](lessons/corrections.md) | 35 | every review |

A numbered file (`claims-2.md`) continues the one before it; an area's parts
are read together.

**Adding a lesson.** Put it at the top of the area's first file, with the next
free number (`tests/review-lessons` prints it). When a file passes 30 kB, move
its oldest entries, from the bottom, to the top of the area's next part (make
one if there is none) and add it to the table above. `tests/review-lessons`
fails on a file over 40 kB, which is about what one read holds, on a number
used twice or missing, and on a file the table doesn't list.
