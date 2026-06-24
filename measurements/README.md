# Measurements

Memory and performance notes for CalmPage Native spikes.

## Commands

```bash
ps -o pid,rss,vsz,etime,command -p <pid>
vmmap -summary <pid>
```

## Test States

- cold start
- folder loaded
- normal note open
- huge note open
- two tabs open
- all tabs closed
