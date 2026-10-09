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

[`pyproject.toml`](pyproject.toml) selects Python 3.12, Dora CLI 1.0.0 or later
(`uv.lock` currently resolves 1.0.1 because some nodes cap `dora-rs` at `<= 1.0.1`),
and all node dependencies, including `openarm-driver>=0.5.1`.
uv creates `.venv` in this repository and downloads a compatible Python if needed;
no `.python-version` file is required. Nodes under `nodes/` are installed editable,
so Python source edits take effect after restarting the node. The parent project
manages the shared environment and is not installed as a Python package.

Run the desired dataflow from the same activated shell. For example,
to use WebXR with MuJoCo (no real arms required):

```bash
./nodes/dora-openarm-webxr/example/prepare_tls.sh "$(hostname).local"
dora run dataflow-webxr-mujoco.yaml --uv
```

See the WebXR section below for browser URLs and TLS details. Other dataflows
use `dora run <dataflow>.yaml --uv`, with their own hardware prerequisites.
The root dataflows have no package-installing `build` commands; `uv sync --locked`
installs their dependencies, so a separate `dora build` step is not needed.

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

Each dataflow uses the same metadata file for its UI and recorder:

| Dataflows | Metadata | Recorded equipment |
|---|---|---|
| KER, VR, WebXR (real Cell) | [`metadata.yaml`](metadata.yaml) | Arms, lifter, five cameras |
| VR/WebXR MuJoCo | [`metadata_mujoco.yaml`](metadata_mujoco.yaml) | Arms, five simulated cameras |
| Pedestal | [`metadata_pedestal.yaml`](metadata_pedestal.yaml) | Arms only |
| Dummy | [`metadata_dummy.yaml`](metadata_dummy.yaml) | Arms, four dummy cameras (`head` is a single stream) |

### KER configuration

[`dataflow-ker.yaml`](dataflow-ker.yaml) is a configuration for leader-follower teleoperation with real OpenArm units and cameras. A [KER](https://github.com/enactic/dora-openarm-ker) leader arm controls the follower arms while wrist, head and ceiling cameras are recorded.

The Cell lifter receives the shared 250 Hz tick and records its elevation action
and observation in millimeters. It uses its built-in startup calibration and hold
behavior; this flow has no interactive lift control input. A real lifter is
required on `can2` by default, and startup enables and moves it for calibration.

### VR configuration

[`dataflow-vr.yaml`](dataflow-vr.yaml) is a configuration for VR teleoperation with real OpenArm units and cameras. VR controller poses are received over UDP by [dora-openarm-vr](https://github.com/enactic/dora-openarm-vr), converted to joint positions by inverse kinematics ([dora-openarm-kinematics](https://github.com/enactic/dora-openarm-kinematics)) and sent to the follower arms.

[`dataflow-vr-mujoco.yaml`](dataflow-vr-mujoco.yaml) is the same VR teleoperation but with a MuJoCo simulation ([dora-openarm-mujoco](https://github.com/enactic/dora-openarm-mujoco)) instead of real OpenArm units and cameras. We can use this for testing VR teleoperation and data collection without real hardware.

### WebXR configuration

[`dataflow-webxr-mujoco.yaml`](dataflow-webxr-mujoco.yaml) is a configuration for WebXR teleoperation with a MuJoCo simulation. [dora-openarm-webxr](https://github.com/enactic/dora-openarm-webxr) starts a Web server and the Web browser on a VR device such as Meta Quest 3 or PICO 4 connects to it to stream controller poses. No native VR application is needed.

WebXR requires HTTPS, so a TLS certificate is needed. A self-signed certificate is enough; see the [dora-openarm-webxr setup instructions](https://github.com/enactic/dora-openarm-webxr#setup) for how to generate one. Then run:

```bash
./nodes/dora-openarm-webxr/example/prepare_tls.sh $(hostname).local
dora run dataflow-webxr-mujoco.yaml --uv
```

Open http://localhost:8000/ on the local machine for the data collection UI, and open `https://${YOUR_HOST_NAME}:8443/` in the Web browser on your VR device (where `${HOSTNAME}` matches the value passed to `prepare_tls.sh`) to start teleoperation.

### Dummy configuration

[`dataflow_dummy.yaml`](dataflow_dummy.yaml) is a configuration that doesn't use real OpenArm. We can use this for testing a dataflow without real OpenArm.

### Switchable configuration (experimental)

[`dataflow/dataflow-main.yaml`](dataflow/dataflow-main.yaml) merges the KER, VR, WebXR and dummy configurations into one dataflow. Environment variables pick the leader and the robot through [dora-openarm-selector](https://github.com/enactic/dora-openarm-selector) nodes:

| Variable | Values | Default |
|---|---|---|
| `LEADER` | `ker`, `vr`, `webxr`, `dummy` | `ker` |
| `ROBOT` | `cell` (real Cell), `mujoco`, `dummy` | `cell` |

Run it from the `dataflow/` directory, because nodes use it as their working directory and file paths in it start with `../`. Set `METADATA_FILE` to match `ROBOT` (default: `../metadata.yaml`):

```bash
cd dataflow
LEADER=webxr ROBOT=mujoco METADATA_FILE=../metadata_mujoco.yaml dora run dataflow-main.yaml --uv
```

Nodes that need hardware or a port (KER, VR/WebXR receivers, followers, lifter, cameras, MuJoCo) run through `dora-openarm-standby`. When they aren't selected, they stand by without opening any device, so `LEADER=dummy ROBOT=dummy` needs no hardware. Datasets are recorded under `data/<LEADER>-<ROBOT>/`. The pedestal configuration isn't merged because its followers use another `--config` on the same CAN buses.

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
