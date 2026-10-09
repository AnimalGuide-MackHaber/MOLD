#!/bin/bash
set -e
cd "$(dirname "$0")/.."
JDK=/Applications/Processing.app/Contents/app/resources/jdk/bin
CORE=/Applications/Processing.app/Contents/app/resources/core/library/core-4.5.7.jar
mkdir -p tests/build/gen tests/build/bench
python3 tests/pde_to_java.py tests/build/gen/MoldSketch.java
"$JDK/javac" -nowarn -d tests/build/bench -cp "$CORE" \
  tests/build/gen/MoldSketch.java FastFFT.java PartitionedConvolver.java VelvetImpulseGenerator.java tests/MoldBench.java
"$JDK/java" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldBench
