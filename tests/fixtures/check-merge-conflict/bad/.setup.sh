# The hook only checks during a merge, so fake the merge state.
touch .git/MERGE_MSG
printf '0000000000000000000000000000000000000000\n' >.git/MERGE_HEAD
# Markers generated here so this repo never contains a real-looking conflict.
printf '%s HEAD\nours\n%s\ntheirs\n%s branch\n' '<<<<<<<' '=======' '>>>>>>>' >notes.txt
