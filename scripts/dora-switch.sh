#!/bin/sh
# Copyright 2026 Enactic, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runs a dora command on dataflow/robot-$ROBOT.yaml (default: cell) with
# ${VAR:-default} in its `module:` paths expanded, because dora doesn't expand
# them:
#
#   LEADER=webxr ROBOT=mujoco scripts/dora-switch.sh run --uv
#   scripts/dora-switch.sh validate
#
# The expanded file is written next to robot-$ROBOT.yaml so that module paths
# and the nodes' working directory stay the same.
set -eu

if [ $# -lt 1 ]; then
    echo "Usage: [LEADER=...] [ROBOT=...] $0 <dora command> [args...]" >&2
    exit 1
fi

# Generated motion must never move the real arms.
if [ "${LEADER:-ker}" = dummy ] && [ "${ROBOT:-cell}" = cell ]; then
    echo 'LEADER=dummy with ROBOT=cell would move the real arms; use ROBOT=mujoco or ROBOT=dummy.' >&2
    exit 1
fi

cd "$(dirname "$0")/../dataflow"

input="robot-${ROBOT:-cell}.yaml"
if [ ! -f "$input" ]; then
    echo "Unknown ROBOT=${ROBOT:-}: dataflow/$input doesn't exist." >&2
    exit 1
fi

output=".robot-${ROBOT:-cell}-${LEADER:-ker}.yaml"
perl -pe '
    s/\$\{(\w+)(?::-([^}]*))?\}/(defined $ENV{$1} && $ENV{$1} ne "") ? $ENV{$1} : ($2 \/\/ "")/ge
        if /^\s*module:/;
' "$input" > "$output"

command=$1
shift
exec dora "$command" "$output" "$@"
