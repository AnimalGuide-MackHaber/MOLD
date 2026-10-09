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

echo ""
echo "Verifying Antigravity and Claude Code skills parity..."
diff -r .agents/skills .claude/skills
python3 -c '
import os
for base in [".agents/skills", ".claude/skills"]:
    assert os.path.isdir(base), f"Missing {base}"
    skills = [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d))]
    assert len(skills) >= 6, f"Expected at least 6 skills in {base}, got {len(skills)}"
    for s in skills:
        skill_file = os.path.join(base, s, "SKILL.md")
        assert os.path.isfile(skill_file), f"Missing SKILL.md in {skill_file}"
        with open(skill_file) as f:
            content = f.read()
        assert content.startswith("---"), f"{skill_file} missing YAML frontmatter"
        assert f"name: {s}" in content, f"{skill_file} name mismatch"
        assert "description:" in content, f"{skill_file} missing description"
print(">> ALL ANTIGRAVITY & CLAUDE CODE SKILLS VALIDATED & IN SYNC! <<")
'

