# shellcheck shell=bash
# Shared Firstmate tool compatibility floors, release-channel identities, and
# intentionally pinned CI versions.
# Usage: . bin/fm-tool-versions-lib.sh
#
# Compatibility floors answer only whether an installed tool is supported by
# tracked Firstmate behavior. They are not claims about the newest release and
# do not drift merely because a newer stable version is published.
# bin/fm-version-inventory.sh separately performs an explicit, bounded,
# read-only freshness check against the release channels named here.
#
# Exact CI pins remain fixed until their owning real-tool matrix is re-verified.
# They are intentionally distinct from both compatibility floors and the latest
# stable release.

FM_NO_MISTAKES_MIN=1.31.2
FM_GH_AXI_MIN=0.1.29
FM_LAVISH_AXI_MIN=0.1.46
FM_TASKS_AXI_MIN=0.2.4
FM_QUOTA_AXI_MIN=0.1.25

FM_NO_MISTAKES_RELEASE_REPO=kunchenguid/no-mistakes
FM_TREEHOUSE_CI_VERSION=2.0.1
FM_TREEHOUSE_CI_REPO=kunchenguid/treehouse
FM_HERDR_CI_VERSION=0.7.4
FM_HERDR_CI_REPO=ogulcancelik/herdr

# Herdr compatibility is protocol-based. Version freshness alone cannot prove
# this floor, so the maintenance inventory reports the floor but never starts or
# queries a live Herdr server to claim compatibility.
FM_BACKEND_HERDR_MIN_PROTOCOL=14
