# The hook only checks during a merge, so fake the merge state.
touch .git/MERGE_MSG
printf '0000000000000000000000000000000000000000\n' >.git/MERGE_HEAD
