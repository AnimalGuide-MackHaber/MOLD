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
