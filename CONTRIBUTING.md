# Contributing to Omnie Edit

Omnie Edit is developed locally with Xcode. A hosted repository is not required to build, test, or contribute.

## Before changing code

1. Read `BUILD_PLAN.md` for product scope.
2. Keep user files in place; never introduce a private shadow copy of an opened document.
3. Keep security-scoped access balanced and coordinate external file reads and writes.
4. Preserve the one-handed interaction model in both right- and left-handed modes.

## Code style

- Prefer small Swift types with one clear responsibility.
- Use four-space indentation and descriptive names.
- Use Swift concurrency rather than Combine for new asynchronous work.
- Explain non-obvious constraints and decisions, not syntax.
- Avoid force unwraps and hidden global state.
- Keep third-party frameworks behind narrow integration boundaries.

## Tests

Run Product > Test in Xcode before sharing a change. File-system features should use temporary directories and test both success and failure paths. UI changes should be checked on an iPhone simulator in both preferred-hand modes.

## Changes that need extra care

Bookmark handling, recursive deletion, autosave, Git operations, signing, and dependency updates can affect user data or distribution. Keep these changes focused and document the verification performed.
