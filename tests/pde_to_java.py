#!/usr/bin/env python3
"""Concatenate the sketch's .pde tabs into one compilable Java class (MoldSketch)
so simulation/audio code can be benchmarked and tested headlessly with javac.
Mimics the parts of the Processing preprocessor this sketch relies on."""
import re, sys, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
PDES = ['MOLD.pde', 'Simulation.pde', 'FoodNodule.pde', 'Harmony.pde', 'Render.pde',
        'Controls.pde', 'UI.pde', 'Midi.pde', 'Audio.pde']
PUBLIC = ('void settings()', 'void setup()', 'void draw()', 'void exit()', 'void mousePressed()',
          'void mouseDragged()', 'void mouseReleased()', 'void keyPressed()')

out = sys.argv[1]
imports = ['import processing.core.*;\n', 'import processing.opengl.*;\n']
body = []
settings_lines = []
in_setup = False
setup_brace_depth = 0

for pde in PDES:
    with open(os.path.join(ROOT, pde)) as f:
        for line in f.read().splitlines():
            if line.startswith('import '):
                imports.append(line + '\n')
                continue
            l = re.sub(r'\bint\(', '(int)(', line)
            l = re.sub(r'\bfloat\(', '(float)(', l)
            l = re.sub(r'\bcolor\s+(?=\w+\s*=)', 'int ', l)
            if l.startswith(PUBLIC):
                l = 'public ' + l

            # Mimic Processing preprocessor: extract settings-level statements from setup()
            stripped = l.strip()
            if 'void setup()' in l:
                in_setup = True
                setup_brace_depth = 0
            if in_setup:
                setup_brace_depth += l.count('{') - l.count('}')
                if stripped.startswith(('fullScreen(', 'pixelDensity(', 'noSmooth();', 'smooth(')):
                    settings_lines.append('    ' + stripped + '\n')
                    continue
                if setup_brace_depth <= 0 and ('{' in l or (in_setup and not 'void setup()' in l)):
                    in_setup = False

            body.append(l + '\n')

# If settings statements were extracted from setup, insert public void settings()
if settings_lines:
    settings_block = ['  public void settings() {\n'] + settings_lines + ['  }\n\n']
    body = settings_block + body

with open(out, 'w') as f:
    f.write(''.join(imports) + 'public class MoldSketch extends PApplet {\n' + ''.join(body) + '}\n')
