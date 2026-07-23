#!/bin/sh
# Runs the repo's three checks and captures everything into check.log at the
# repo root, so the log can be read directly from the project folder (e.g. by
# Claude over the folder bridge) instead of being copy-pasted around.
{
  echo "== dart format =="
  dart format lib test
  echo "== flutter analyze =="
  flutter analyze
  echo "== flutter test (failures shown in github reporter style) =="
  flutter test -r github
  echo "== done, exit=$? =="
} >check.log 2>&1
tail -5 check.log
