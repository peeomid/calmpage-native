# Task 6 Measurement Run - Regression Gates

## Summary

- Added model-level debug counters for optimization regression checks.
- Cold launch RSS was sampled after building and launching the release app.
- Current automated gate: `swift test` plus `AppModel.debugCounters` assertions.

## Terms/context

- RSS: real memory used by the app process.
- Debug counters: simple numbers from app state, used by tests and manual checks.
- Visible rows: current capped file list shown by the library query.

## Overview

- Counters added
  - roots count: `debugCounters.rootsCount`
  - indexed file count: `debugCounters.indexedFileCount`
  - open tab count: `debugCounters.openTabCount`
  - loaded note count: `debugCounters.loadedNoteCount`
  - visible row count: `debugCounters.visibleRowCount`

- Manual memory checkpoints to record on app launch
  - cold launch RSS: 110,304 KB after 3 seconds, PID 55208
  - after restored roots: pending
  - during indexing: pending
  - after indexing: pending
  - normal note open: pending
  - huge note open: pending
  - close all tabs: pending

- Commands

```bash
pgrep -fl CalmPageNative
ps -o pid,rss,vsz,etime,command -p <pid>
vmmap -summary <pid>
```

- Regression rule
  - If RSS or counters grow unexpectedly, add a note here with the cause before accepting the change.
  - Expected loaded note count after `closeAllTabs()`: `0`.
  - Expected open tab count after `closeAllTabs()`: `0`.
