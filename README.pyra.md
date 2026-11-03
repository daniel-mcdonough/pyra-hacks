# pyra-hacks, with the Pyra port's changes

This is not the upstream repository. Upstream is
https://dev.pyra-handheld.com/packages/pyra-hacks.git, which is not
publicly readable, so `main` is rebuilt from the released source packages
(0.30 to 0.38, from the package archive): one commit and one tag per
release, with author and date taken from that release's changelog entry.
`main` is never changed by hand.

Each change lives on its own branch off `main`, and is exactly the patch to
send upstream:

    git diff main...feature/volumed-taper
    git format-patch main..feature/thermal-ladder

| branch | what | dragonbox-pyra |
| --- | --- | --- |
| `feature/thermal-cap` | apply the ceiling through `scaling_max_freq`; `cpufreq-set` is not in trixie | fix 6 |
| `feature/thermal-ladder` | the ladder's five decision faults; on top of `thermal-cap` | fix 7 |
| `feature/volumed-taper` | the volume wheel through its measured taper, calibration in `/etc/pyra_volumed.conf` | fix 12 |

`pyra` merges all of them, then adds two local commits: one that puts back
the marker comments dragonbox-pyra's device scripts use to recognise an
already-fixed `pyra-thermal.sh` (they mean nothing upstream, so the feature
branches leave them out), and the packaging (a `+pyraN` version and this
file) last. That is the branch that gets built:

    ./pc/pyra-crossbuild.sh pyra-hacks          # from the dragonbox-pyra checkout

The packaging commit is never part of a feature branch, so it never shows
up in a patch.

A last local commit adds `.github/workflows/build.yml`, which runs the same
cross build on every push to `pyra`. Pushing a tag that names the
changelog's version, such as `v0.38+pyra1`, publishes the debs as a
release; the workflow fails if the tag and `debian/changelog` disagree.

The thermal branches carry the output of dragonbox-pyra's
`device/pyra-thermal-fix.sh` and `device/pyra-thermal-ladder.sh`
(`--emit-patched`) applied to the 0.38 script. Those scripts, and the
prep script's fixes 6, 7 and 12, edit or override the installed package
in place. A card with this package installed does not need them. They stay
in dragonbox-pyra's master for cards running the stock package.
