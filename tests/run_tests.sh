#!/bin/bash
set -e
cd "$(dirname "$0")/.."
JAVAC=/Applications/Processing.app/Contents/app/resources/jdk/bin/javac
JAVA=/Applications/Processing.app/Contents/app/resources/jdk/bin/java

mkdir -p tests/build
echo "Compiling DSP verification suite..."
"$JAVAC" -d tests/build FastFFT.java PartitionedConvolver.java VelvetImpulseGenerator.java tests/ConvolverVerificationTest.java

echo "Running ConvolverVerificationTest..."
"$JAVA" -cp tests/build ConvolverVerificationTest

echo ""
echo "Compiling and running Mold test suites..."
CORE=/Applications/Processing.app/Contents/app/resources/core/library/core-4.5.7.jar
mkdir -p tests/build/gen tests/build/bench
python3 tests/pde_to_java.py tests/build/gen/MoldSketch.java
"$JAVAC" -nowarn -d tests/build/bench -cp "$CORE" \
  tests/build/gen/MoldSketch.java FastFFT.java PartitionedConvolver.java VelvetImpulseGenerator.java tests/MoldTestUtils.java \
  tests/MoldReverbModTest.java tests/MoldStereoSpatializationTest.java tests/MoldMidiControllerTest.java \
  tests/MoldSimulationInvariantsTest.java tests/MoldAudioStabilityTest.java tests/MoldHeadlessSmokeTest.java
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldReverbModTest
echo ""
echo "Running MoldStereoSpatializationTest..."
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldStereoSpatializationTest
echo ""
echo "Running MoldMidiControllerTest..."
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldMidiControllerTest
echo ""
echo "Running MoldSimulationInvariantsTest..."
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldSimulationInvariantsTest
echo ""
echo "Running MoldAudioStabilityTest..."
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldAudioStabilityTest
echo ""
echo "Running MoldHeadlessSmokeTest..."
"$JAVA" -Djava.awt.headless=true -cp "tests/build/bench:$CORE" MoldHeadlessSmokeTest

