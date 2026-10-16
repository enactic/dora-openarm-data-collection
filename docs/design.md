# Dataflow design

This describes how [`dataflow.yaml`](../dataflow.yaml) and its leader and robot
modules are structured, and the rules to follow when we change them or add a
new leader or robot.

## Modules

`dataflow.yaml` has the nodes that every configuration uses: the UI, the ticks,
the recorder, and the `leader` and `robot` modules. `LEADER` picks
`leader-$LEADER.yaml` and `ROBOT` picks `robot-$ROBOT.yaml`.

dora doesn't expand environment variables in `module:` paths
([dora-rs/dora#3805](https://github.com/dora-rs/dora/issues/3805)), so we run
the dataflow through [`scripts/dora-envsubst`](../scripts/dora-envsubst).

### Common inputs and outputs

All leader modules declare the same inputs and outputs, and so do all robot
modules, so that `dataflow.yaml` can wire whichever one is picked.

- A module ignores inputs that it doesn't use. dora accepts a declared input
  that no inner node uses.
- A module declares outputs that it doesn't have on a node that never sends
  them, with a `# Not sent by ...` comment. dora requires each declared output
  to have exactly one inner node that has an output with the same name.
- When we add an input or output to a leader or a robot, we add it to all
  leader or robot modules.

See [`leader-ker.yaml`](../leader-ker.yaml) and
[`robot-cell.yaml`](../robot-cell.yaml) for the inputs and outputs with
comments.

### Renaming outputs

A module output has the name of the inner node's output, and dora has no way to
map another name to it. When an inner node's output has another name than the
common one, or two inner nodes have outputs with the same name, e.g. `image` of
each camera, we forward them through a node whose input IDs are the common
names:

- `dora-echo` when the node doesn't need to close anything on Quit.
- `dora-openarm-quitter` when it also needs to close its outputs on Quit; see
  [Quit](#quit).

We don't use `dora-openarm-quitter` only to rename outputs.

### Where modules are

The modules are next to `dataflow.yaml`, not in a subdirectory. dora resolves
`path:` in a module relative to the module file, so `path: dora-openarm` in
`modules/robot-cell.yaml` would become `modules/dora-openarm` and wouldn't be
found in `PATH`.

## Quit

The UI sends `quit` as `ui/command` on Quit. Then the whole dataflow must stop
without waiting for anything else.

### How nodes stop

A node stops when its loop over events ends. With `for event in node`, that's
when all its inputs are closed, unless the node breaks the loop earlier, e.g. on
`STOP` or `INPUT_CLOSED`. An input is closed when its source node stops. So a
node stops on Quit only when everything that it depends on stops on Quit.

`dora-openarm-quitter` stops when it receives `quit` on its `command` input, so
it closes its outputs on Quit regardless of its other inputs.
`quittable-tick-leader` and `quittable-tick-camera` in `dataflow.yaml` use it to
close the ticks on Quit.

### Leaders and robots wait for each other

The robot uses the leader's outputs, e.g. the target positions, and the leader
may use the robot's outputs, e.g. WebXR shows the head camera and stops only
when its camera inputs are closed. If the robot's cameras also wait for the
leader, e.g. MuJoCo renders them from the leader's targets, they wait for each
other and never stop.

To avoid it, the robot closes the outputs that a leader may use on Quit by
itself:

- A node whose inputs are only `_mod/tick`, `_mod/camera_tick` or outputs of
  such nodes stops by itself on Quit because the ticks are closed on Quit. The
  cameras of the Cell and dummy robots and the `cameras` relays of them are
  such nodes.
- A node that produces outputs that a leader may use, e.g. `camera_*`, and has
  other inputs, e.g. the leader's targets, must get the other inputs through a
  `dora-openarm-quitter` with `command: _mod/command`. The MuJoCo robot's
  `quittable-controls` does this for all inputs from the leader.
- Outputs that are never sent and that a leader may use must be declared on a
  `dora-openarm-quitter` with only `command: _mod/command`, not on a node that
  waits for the leader. The pedestal's `quittable-cameras` does this.

A node that uses the leader's outputs but doesn't produce outputs that a leader
uses, e.g. the followers of the Cell, doesn't need a quitter: it stops after the
leader stops.

The leader's nodes stop when `_mod/tick` is closed and the robot closes its
outputs on Quit. So a leader doesn't need its own quitter for Quit.

### Naming

A node that uses `dora-openarm-quitter` is named `quittable-*`, e.g.
`quittable-controls`, so that we can see which nodes close their outputs on
Quit.
