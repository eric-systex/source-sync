## Summary
Source Sync

## Usage
- `./run.sh conf/<project>.conf [repo_name|--all]`
- `./sync.sh <conf> <name> <source> <target>` (normally invoked by `run.sh`)

## Config parameters
- `AWS_ACCOUNT_ID`, `AWS_PROFILE_NAME`, `AWS_REGION`, `SNS_SUBJECT_PREFIX`
- `TOKEN`
- `REPOS=("name|source|target")` replaces the parallel arrays; an empty source defaults to name.

