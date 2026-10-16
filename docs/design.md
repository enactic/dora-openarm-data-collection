# Dataflow design

The rules to follow when we change [`dataflow.yaml`](../dataflow.yaml) and its
leader and robot modules, or add a new leader or robot.

## Modules

`dataflow.yaml` has the UI, the ticks, the recorder, and the `leader` and
`robot` modules. `LEADER` picks `leader-$LEADER.yaml` and `ROBOT` picks
`robot-$ROBOT.yaml`.

### Common inputs and outputs

All leader modules declare the same inputs and outputs, and so do all robot
modules, so that `dataflow.yaml` can wire whichever one is picked. See
[`leader-ker.yaml`](../leader-ker.yaml) and
[`robot-cell.yaml`](../robot-cell.yaml) for them.

- When we add an input or output, we add it to all leader or robot modules.
- A module ignores inputs that it doesn't use.
- A module declares outputs that it doesn't have on a node that never sends
  them, with a `# Not sent by ...` comment, because dora requires each module
  output to have an inner node with an output of the same name.

### Renaming outputs

dora can't give a module output another name than the inner node's output. So
when the names differ, or two inner nodes have the same output name, e.g.
`image` of each camera, we forward the outputs through a node whose input IDs
are the common names. We use `dora-echo` for it, or `dora-openarm-quitter` when
the node also needs to close its outputs on Quit; see [Quit](#quit).

### Where modules are

The modules are next to `dataflow.yaml`. dora resolves `path:` in a module
relative to the module file, so `path: dora-openarm` in
`modules/robot-cell.yaml` would become `modules/dora-openarm` and wouldn't be
found in `PATH`.

## Quit

On Quit, the UI sends `quit` as `ui/command`, and the whole dataflow must stop.

A node stops when all its inputs are closed, and an input is closed when its
source node stops. `dora-openarm-quitter` stops when it receives `quit` on its
`command` input, so its outputs close on Quit regardless of its other inputs.
`quittable-tick-leader` and `quittable-tick-camera` close the ticks this way.

The leader and the robot may wait for each other: e.g. WebXR stops only when
the robot's head cameras are closed, and MuJoCo renders the cameras from the
leader's targets. So a robot must close the outputs that a leader uses, e.g.
`camera_*`, on Quit without waiting for the leader:

- A node that depends only on `_mod/tick` and `_mod/camera_tick` stops by
  itself, e.g. the cameras of the Cell and dummy robots.
- A node that also depends on the leader must get the leader's outputs through
  a `dora-openarm-quitter`, e.g. the MuJoCo robot's `quittable-controls`.
- Outputs that are never sent must be declared on a `dora-openarm-quitter` with
  only `command: _mod/command`, e.g. the pedestal's `quittable-cameras`.

Other nodes, e.g. the followers, and the leaders stop after what they depend on
stops, so they don't need a quitter.

A node that uses `dora-openarm-quitter` is named `quittable-*`.
