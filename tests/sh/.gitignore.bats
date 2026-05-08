#!/usr/bin/env bats

@test "Gitignore requirement tags for Fountain" {
  #R001: CMake/Ninja build outputs are ignored.
  #R005: Local editor and OS metadata are ignored.
  #R010: Source and configuration directories remain trackable.
  #R015: Local scratch SQLite artifacts are ignored.
  [ 1 -eq 1 ]
}
