# Summary

<!--
What this change does, in plain English, without dumbing down the technical
details. Don't enumerate the code changes — the diff already does that.
Keep it to a length a reviewer will actually read.
-->

# Dependencies

<!--
Anything that has to ship, deploy or be configured before this can merge.
Remove this section when there are none.
-->

# How to test

## Setup

<!--
Any setup that isn't obvious. Remove this section when nothing out of the
ordinary is needed.
-->

## Steps

<!--
A numbered list, one action per step, in the order they are performed, ending
at the behavior this change affects. Leave out any step the reviewer would
take without being told, and leave out the section if it would be left empty.
-->

## Old behavior

<!--
Required. The behavior before this change, in plain English, without dumbing
down the technical details. Keep it concise and clearly structured. Don't
enumerate the code changes — the diff already does that. A screenshot or GIF is
required when the change has user-facing consequences.
-->

## New behavior

<!--
Required. The behavior after this change, in plain English, without dumbing
down the technical details. Keep it concise and clearly structured. Don't
enumerate the code changes — the diff already does that. A screenshot or GIF is
required when the change has user-facing consequences.
-->

# Checklist

- [ ] I have added integration tests proving that the feature works or the fix is effective
- [ ] I have mocked a dependency only where an integration test could not cover the same behaviour
- [ ] I have squashed the branch to commits in conventional commits format that each stand on their own
- [ ] I have updated the docs to match this change
- [ ] I have added an ADR for any major or architectural decision this change makes
