## Summary
Replace the three duplicated script pairs (maple/gemma/palm `*-run.sh` / `*-sync.sh`) with a single `run.sh` and `sync.sh` that read all group-specific values from a config file.

## Usage
- `./run.sh conf/<group>.conf [repo_name|--all]`
- `./sync.sh <conf> <name> <source> <target>` (normally invoked by `run.sh`)

## Config parameters (`conf/maple.conf`, `conf/gemma.conf`, `conf/palm.conf`)
- `AWS_ACCOUNT_ID`, `AWS_PROFILE_NAME`, `AWS_REGION`, `SNS_TOPIC_NAME`, `SNS_SUBJECT_PREFIX`
- `TOKEN`, `WORKING_HOME`
- `SOURCE_URL_BASE`, `TARGET_URL_BASE`
- `REPOS=("name|source|target")` replaces the parallel arrays; an empty source defaults to name (palm).

## Notes
- `TARGET_URL_BASE` retains the masked `******git.systex.com` from the originals; fill in the real value.
- `TOKEN` was unused in the original scripts and still is; configs hold it in plaintext, so avoid committing real secrets.
- Result temp file is now `result.$name.tmp` to avoid collisions.

## Testing
`bash -n` on both scripts, all three configs load (15/16/10 repos), and invalid repo name handling verified. No real sync or SNS publish was run.
