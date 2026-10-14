# Data collection configurations for OpenArm with dora-rs

This repository provides data collection configurations for [OpenArm](https://openarm.dev/) with [dora-rs](https://dora-rs.ai/).

## Setup

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) and Git,
then run the following from the repository root after cloning:

```bash
git submodule update --init --recursive
uv sync --locked
source .venv/bin/activate
```

[`pyproject.toml`](pyproject.toml) selects Python 3.12, Dora 1.0.x
(`dora-rs` and `dora-rs-cli` are kept on the same version; `uv.lock` resolves 1.0.1),
and all node dependencies, including `openarm-driver>=0.5.1`.
uv creates `.venv` in this repository and downloads a compatible Python if needed;
no `.python-version` file is required. Nodes under `nodes/` are installed editable,
so Python source edits take effect after restarting the node. The parent project
manages the shared environment and is not installed as a Python package.

Run the dataflow from the same activated shell. [`dataflow.yaml`](dataflow.yaml)
picks the leader and the robot by the `LEADER` and `ROBOT` environment variables.
For example, to use WebXR with MuJoCo (no real arms required):

```bash
./nodes/dora-openarm-webxr/example/prepare_tls.sh "$(hostname).local"
LEADER=webxr ROBOT=mujoco scripts/dora-envsubst run dataflow.yaml --uv
```

See [Configurations](#configurations) for the other leaders and robots, and the
WebXR section below for browser URLs and TLS details.
The dataflow has no package-installing `build` commands; `uv sync --locked`
installs its dependencies, so a separate `dora build` step is not needed.

[`uv.lock`](uv.lock) locks the resolved dependency versions. Editable node source
revisions are pinned by this repository's Git submodule commits; the lockfile
does not freeze uncommitted source changes. In each new terminal, run
`source .venv/bin/activate` before invoking `dora` so that it uses this project's
CLI rather than another program with the same name.

Use `uv sync --locked` after pulling updates. It refuses to change an outdated
lockfile and removes packages outside the managed dependency set. To intentionally
update a dependency, run `uv lock --upgrade-package <package>`, then
`uv sync --locked`, test, and commit the lockfile. After changing dependency
declarations or node submodule revisions, run `uv lock` and commit any resulting
lockfile changes along with the TOML or submodule changes.
See [uv's synchronization rules](https://docs.astral.sh/uv/concepts/projects/sync/).

## Configurations

[`dataflow.yaml`](dataflow.yaml) is the only dataflow. The leader and the robot
are modules under [`modules/`](modules) picked by environment variables:

| Variable | Values | Picks | Default |
|---|---|---|---|
| `LEADER` | `ker`, `vr`, `webxr`, `dummy` | `modules/leader-$LEADER.yaml` | `ker` |
| `ROBOT` | `cell` (real Cell), `mujoco`, `dummy` | `modules/robot-$ROBOT.yaml` | `dummy` |

dora doesn't expand environment variables in `module:` paths
([dora-rs/dora#3805](https://github.com/dora-rs/dora/issues/3805)), so run the
dataflow through [`scripts/dora-envsubst`](scripts/dora-envsubst). It expands
`$VAR`, `${VAR}` and `${VAR:-default}` in `module:` paths, writes the result to
`<name>.envsubst.yaml` next to the given dataflow and runs the given dora
command on it:

```bash
LEADER=ker ROBOT=cell scripts/dora-envsubst run dataflow.yaml --uv
```

Only the selected leader and robot are in the dataflow, so the others open no
device or port. All leader modules have the same inputs and outputs, and so do
all robot modules; outputs a module doesn't have are declared but never sent.
`LEADER=dummy` with `ROBOT=cell` moves the real arms with generated motion.

The UI and the recorder use `metadata_$ROBOT.yaml`, and datasets are recorded
under `data/$LEADER-$ROBOT/`, e.g. `data/webxr-mujoco/`:

| Robot | Metadata | Recorded equipment |
|---|---|---|
| `cell` | [`metadata_cell.yaml`](metadata_cell.yaml) | Arms, lifter, five cameras |
| `mujoco` | [`metadata_mujoco.yaml`](metadata_mujoco.yaml) | Arms, five simulated cameras |
| `dummy` | [`metadata_dummy.yaml`](metadata_dummy.yaml) | Arms, five dummy cameras |

Known gaps compared with the previous separate dataflows:

- There is no pedestal robot yet. [`metadata_pedestal.yaml`](metadata_pedestal.yaml)
  is kept for it.
- The WebXR headset gets no head camera view.
- The MuJoCo node runs without `--debug-frames` and the `pose_right`/`pose_left` inputs.
- `ROBOT=cell` has no MuJoCo viewer that mirrors the real arms.

### KER leader

`LEADER=ker` uses a [KER](https://github.com/enactic/dora-openarm-ker) leader arm
connected over USB. Its joint positions are sent to the follower arms directly.

### VR leader

`LEADER=vr` receives VR controller poses over UDP by
[dora-openarm-vr](https://github.com/enactic/dora-openarm-vr), converts them to
joint positions by inverse kinematics
([dora-openarm-kinematics](https://github.com/enactic/dora-openarm-kinematics))
and sends them to the follower arms.

### WebXR leader

`LEADER=webxr` uses [dora-openarm-webxr](https://github.com/enactic/dora-openarm-webxr).
It starts a Web server and the Web browser on a VR device such as Meta Quest 3
or PICO 4 connects to it to stream controller poses. No native VR application is
needed.

WebXR requires HTTPS, so a TLS certificate is needed. A self-signed certificate is enough; see the [dora-openarm-webxr setup instructions](https://github.com/enactic/dora-openarm-webxr#setup) for how to generate one. Then run:

```bash
./nodes/dora-openarm-webxr/example/prepare_tls.sh $(hostname).local
LEADER=webxr ROBOT=mujoco scripts/dora-envsubst run dataflow.yaml --uv
```

Open http://localhost:8000/ on the local machine for the data collection UI, and open `https://${YOUR_HOST_NAME}:8443/` in the Web browser on your VR device (where `${HOSTNAME}` matches the value passed to `prepare_tls.sh`) to start teleoperation.

### Dummy leader

`LEADER=dummy` generates leader motion without any device. With `ROBOT=dummy`,
we can test the dataflow without any hardware.

### Cell robot

`ROBOT=cell` uses real OpenArm units on CAN, the Cell lifter and wrist, head and
ceiling cameras.

The Cell lifter receives the shared 250 Hz tick and records its elevation action
and observation in millimeters. It uses its built-in startup calibration and hold
behavior, and the left joystick of a VR leader moves it. A real lifter is
required on `can2` by default, and startup enables and moves it for calibration.

### MuJoCo robot

`ROBOT=mujoco` uses a MuJoCo simulation
([dora-openarm-mujoco](https://github.com/enactic/dora-openarm-mujoco)) instead
of real OpenArm units and cameras. We can use this for testing teleoperation and
data collection without real hardware.

### Dummy robot

`ROBOT=dummy` doesn't use any hardware. The arms echo their targets and the
cameras send test images.

## Debugging OpenArm libraries

The OpenArm-specific dependency repositories are checked out under [`lib/`](lib/README.md).
Initialize them with `git submodule update --init --recursive`.

Libraries normally come from the package index at the versions in `uv.lock`.
To use an editable library checkout, run the command for the library you need
from the repository root:

```bash
uv add --editable lib/openarm_driver
# Other optional library checkouts:
# uv add --editable lib/openarm_can/python
# uv add --editable lib/openarm_ker
# uv add --editable lib/openarm_control
# uv add --editable lib/openarm_mujoco
```

`uv add --editable` updates the parent dependency declaration, adds a local path
under `[tool.uv.sources]`, updates the lockfile, and syncs the environment.
Restart the dataflow after editing Python code. CAN bindings use
`lib/openarm_can/python`; changes to their C++ code require rebuilding.

To return to the package-index version, remove that library's entry from
`[tool.uv.sources]`, then run `uv lock` and `uv sync --locked`. Keep required
version constraints such as `openarm-driver>=0.5.1`. Avoid separate `uv pip install`
commands for managed dependencies, since they bypass the project lockfile.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

Copyright 2026 Enactic, Inc.

## Code of Conduct

All participation in the OpenArm project is governed by our [Code of Conduct](CODE_OF_CONDUCT.md).
