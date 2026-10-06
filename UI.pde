// =============================================================================
// UI.pde - Self-Contained Widget Toolkit (Zero External Library Dependencies)
// Slider / Toggle / Button / Dropdown / RadioGroup / Row / Section / UIPanel
// Stands in for ControlP5 so the sketch remains drop-in runnable.
// =============================================================================

interface FloatCallback { void on(float v); }
interface BoolCallback { void on(boolean v); }
interface IntCallback { void on(int v); }
interface ActionCallback { void run(); }

// The dropdown whose option list is currently open (drawn last, captures clicks)
Dropdown activeDropdown = null;

final int UI_TEXT = 0xFFE4E4E7;
final int UI_DIM = 0xFFA1A1AA;
final int UI_FILL = 0xFF27272A;
final int UI_BORDER = 0xFF3F3F46;
final int UI_YELLOW = 0xFFFACC15;
final int UI_CYAN = 0xFF06B6D4;
final int UI_GREEN = 0xFF10B981;
final int UI_RED = 0xFFEF4444;

String fitText(String s, float maxW) {
  if (textWidth(s) <= maxW) return s;
  while (s.length() > 1 && textWidth(s + "..") > maxW) s = s.substring(0, s.length() - 1);
  return s + "..";
}

/* STREAMING_CHUNK:Widget base class */
abstract class Widget {
  float x, y, w, h;
  boolean visible = true;

  Widget(float h) { this.h = h; }

  void place(float px, float py, float pw) { x = px; y = py; w = pw; }
  void setVisible(boolean v) { visible = v; }
  boolean hit(float mx, float my) { return visible && mx >= x && mx <= x + w && my >= y && my <= y + h; }

  abstract void draw();
  boolean press(float mx, float my) { return false; }
  void drag(float mx, float my) {}
  void release() {}
}

/* STREAMING_CHUNK:Continuous slider with step quantisation */
class Slider extends Widget {
  String label, suffix;
  float minV, maxV, step, value;
  int decimals;
  FloatCallback cb;
  boolean dragging = false;

  Slider(String label, float minV, float maxV, float step, float value, int decimals, String suffix, FloatCallback cb) {
    super(30);
    this.label = label; this.minV = minV; this.maxV = maxV; this.step = step;
    this.decimals = decimals; this.suffix = suffix; this.cb = cb;
    this.value = constrain(value, minV, maxV);
  }

  void setValue(float v, boolean notify) {
    v = constrain(v, minV, maxV);
    if (step > 0) v = constrain(minV + round((v - minV) / step) * step, minV, maxV);
    if (v != value) {
      value = v;
      if (notify && cb != null) cb.on(value);
    }
  }

  void setFromMouse(float mx) {
    float norm = constrain((mx - x) / w, 0.0f, 1.0f);
    setValue(minV + norm * (maxV - minV), true);
  }

  void draw() {
    textSize(10);
    textAlign(LEFT, TOP);
    fill(UI_TEXT);
    text(label, x, y);
    textAlign(RIGHT, TOP);
    fill(UI_YELLOW);
    text(nf(value, 1, decimals) + suffix, x + w, y);

    float ty = y + 17;
    float norm = (value - minV) / (maxV - minV);
    noStroke();
    fill(UI_FILL);
    rect(x, ty, w, 7, 4);
    fill(dragging ? 0xFFFDE047 : UI_YELLOW);
    rect(x, ty, max(7, w * norm), 7, 4);
    fill(255);
    ellipse(x + w * norm, ty + 3.5f, 11, 11);
  }

  boolean press(float mx, float my) { dragging = true; setFromMouse(mx); return true; }
  void drag(float mx, float my) { if (dragging) setFromMouse(mx); }
  void release() { dragging = false; }
}

/* STREAMING_CHUNK:Latching toggle button */
class Toggle extends Widget {
  String offText, onText;
  boolean state;
  int onColor;
  BoolCallback cb;

  Toggle(String offText, String onText, boolean state, int onColor, BoolCallback cb) {
    super(24);
    this.offText = offText; this.onText = onText; this.state = state; this.onColor = onColor; this.cb = cb;
  }

  void set(boolean v, boolean notify) {
    state = v;
    if (notify && cb != null) cb.on(state);
  }

  void draw() {
    stroke(state ? lerpColor(onColor, 0xFF000000, 0.2f) : UI_BORDER);
    fill(state ? onColor : UI_FILL);
    rect(x, y, w, h, 4);
    fill(state ? 0 : 230);
    textSize(10);
    textAlign(CENTER, CENTER);
    text(fitText(state ? onText : offText, w - 8), x + w / 2, y + h / 2 - 1);
  }

  boolean press(float mx, float my) { set(!state, true); return true; }
}

/* STREAMING_CHUNK:Momentary action button */
class Button extends Widget {
  String label;
  int textColor;
  ActionCallback cb;
  boolean down = false;

  Button(String label, int textColor, ActionCallback cb) {
    super(24);
    this.label = label; this.textColor = textColor; this.cb = cb;
  }

  void draw() {
    stroke(UI_BORDER);
    fill(down ? UI_BORDER : UI_FILL);
    rect(x, y, w, h, 4);
    fill(textColor);
    textSize(10);
    textAlign(CENTER, CENTER);
    text(fitText(label, w - 8), x + w / 2, y + h / 2 - 1);
  }

  boolean press(float mx, float my) {
    down = true;
    if (cb != null) cb.run();
    return true;
  }
  void release() { down = false; }
}

/* STREAMING_CHUNK:Segmented radio group */
class RadioGroup extends Widget {
  String label;
  String[] options;
  int selected;
  int accent;
  IntCallback cb;
  float segTop;

  RadioGroup(String label, String[] options, int selected, int accent, IntCallback cb) {
    super(label.length() > 0 ? 38 : 22);
    this.label = label; this.options = options; this.selected = selected; this.accent = accent; this.cb = cb;
  }

  void draw() {
    segTop = label.length() > 0 ? y + 15 : y;
    textSize(10);
    if (label.length() > 0) {
      textAlign(LEFT, TOP);
      fill(UI_TEXT);
      text(label, x, y);
    }
    float segW = w / options.length;
    textAlign(CENTER, CENTER);
    for (int i = 0; i < options.length; i++) {
      boolean on = (i == selected);
      stroke(on ? lerpColor(accent, 0xFF000000, 0.2f) : UI_BORDER);
      fill(on ? accent : UI_FILL);
      rect(x + i * segW + 1, segTop, segW - 2, 22, 3);
      fill(on ? 0 : 220);
      text(fitText(options[i], segW - 6), x + i * segW + segW / 2, segTop + 10);
    }
  }

  boolean press(float mx, float my) {
    float top = label.length() > 0 ? y + 15 : y;
    if (my < top) return true;
    int idx = constrain(int((mx - x) / (w / options.length)), 0, options.length - 1);
    if (idx != selected) {
      selected = idx;
      if (cb != null) cb.on(selected);
    }
    return true;
  }
}

/* STREAMING_CHUNK:Dropdown selector with floating overlay list */
class Dropdown extends Widget {
  String label;
  String[] options;
  int selected;
  IntCallback cb;
  final float ROW_H = 18;

  Dropdown(String label, String[] options, int selected, IntCallback cb) {
    super(38);
    this.label = label; this.cb = cb;
    setOptions(options, selected);
  }

  void setOptions(String[] opts, int sel) {
    options = (opts == null || opts.length == 0) ? new String[]{"(none)"} : opts;
    selected = constrain(sel, 0, options.length - 1);
  }

  float boxY() { return y + 15; }

  float overlayTop() {
    float below = boxY() + 22;
    float listH = options.length * ROW_H;
    if (below + listH <= height - 4) return below;
    return max(4, boxY() - listH);
  }

  void draw() {
    textSize(10);
    textAlign(LEFT, TOP);
    fill(UI_TEXT);
    text(label, x, y);

    boolean open = (activeDropdown == this);
    stroke(open ? UI_CYAN : UI_BORDER);
    fill(UI_FILL);
    rect(x, boxY(), w, 22, 3);
    fill(230);
    textAlign(LEFT, CENTER);
    text(fitText(options[selected], w - 26), x + 8, boxY() + 10);

    // Caret
    noStroke();
    fill(UI_DIM);
    float cx = x + w - 12;
    float cy = boxY() + 11;
    if (open) triangle(cx - 4, cy + 2, cx + 4, cy + 2, cx, cy - 3);
    else triangle(cx - 4, cy - 2, cx + 4, cy - 2, cx, cy + 3);
  }

  void drawOverlay() {
    float top = overlayTop();
    float listH = options.length * ROW_H;
    stroke(UI_CYAN);
    fill(0xFF18181B);
    rect(x, top, w, listH, 3);
    textSize(10);
    textAlign(LEFT, CENTER);
    noStroke();
    for (int i = 0; i < options.length; i++) {
      float ry = top + i * ROW_H;
      boolean hover = mouseX >= x && mouseX <= x + w && mouseY >= ry && mouseY < ry + ROW_H;
      if (i == selected) { fill(UI_CYAN); rect(x + 1, ry + 1, w - 2, ROW_H - 2, 2); }
      else if (hover) { fill(UI_BORDER); rect(x + 1, ry + 1, w - 2, ROW_H - 2, 2); }
      fill(i == selected ? 0 : 230);
      text(fitText(options[i], w - 16), x + 8, ry + ROW_H / 2 - 1);
    }
  }

  // Called while the overlay is open; any click closes it
  void pressOverlay(float mx, float my) {
    float top = overlayTop();
    if (mx >= x && mx <= x + w && my >= top && my < top + options.length * ROW_H) {
      int idx = constrain(int((my - top) / ROW_H), 0, options.length - 1);
      if (idx != selected) {
        selected = idx;
        if (cb != null) cb.on(selected);
      }
    }
    activeDropdown = null;
  }

  boolean press(float mx, float my) {
    if (my >= boxY()) activeDropdown = this;
    return true;
  }
}

/* STREAMING_CHUNK:Horizontal row container */
class Row extends Widget {
  Widget[] kids;
  final float GAP = 8;

  Row(Widget... kids) {
    super(0);
    this.kids = kids;
    for (Widget k : kids) h = max(h, k.h);
  }

  void place(float px, float py, float pw) {
    super.place(px, py, pw);
    float kw = (pw - GAP * (kids.length - 1)) / kids.length;
    for (int i = 0; i < kids.length; i++) kids[i].place(px + i * (kw + GAP), py, kw);
  }

  void setVisible(boolean v) {
    visible = v;
    for (Widget k : kids) k.setVisible(v);
  }

  void draw() { for (Widget k : kids) k.draw(); }

  Widget pressed = null;
  boolean press(float mx, float my) {
    for (Widget k : kids) {
      if (k.hit(mx, my) && k.press(mx, my)) { pressed = k; return true; }
    }
    return false;
  }
  void drag(float mx, float my) { if (pressed != null) pressed.drag(mx, my); }
  void release() { if (pressed != null) pressed.release(); pressed = null; }
}

/* STREAMING_CHUNK:Collapsible section with header */
class Section {
  String title;
  boolean collapsed;
  Widget[] kids;
  float headerY;
  int openStamp = 0;
  final float HEADER_H = 20;

  Section(String title, boolean collapsed, Widget... kids) {
    this.title = title; this.collapsed = collapsed; this.kids = kids;
  }
}

/* STREAMING_CHUNK:Panel managing layout, rendering and mouse dispatch */
class UIPanel {
  float x, y, w, bottom;
  ArrayList<Section> sections = new ArrayList<Section>();
  Widget active = null;
  int stampCounter = 0;
  float contentBottom = 0;

  UIPanel(float x, float y, float w, float bottom) {
    this.x = x; this.y = y; this.w = w; this.bottom = bottom;
  }

  void updateBounds(float nx, float ny, float nw, float nbottom) {
    this.x = nx; this.y = ny; this.w = nw; this.bottom = nbottom;
    layout();
  }

  void add(Section s) {
    s.openStamp = ++stampCounter;
    sections.add(s);
  }

  void layout() {
    float cy = y;
    for (Section s : sections) {
      s.headerY = cy;
      cy += s.HEADER_H + 6;
      for (Widget k : s.kids) {
        k.setVisible(!s.collapsed);
        if (!s.collapsed) {
          k.place(x + 10, cy, w - 20);
          cy += k.h + 6;
        }
      }
      cy += 2;
    }
    contentBottom = cy;
  }

  // Expand a section; collapse least-recently-opened others until everything fits
  void expand(Section target) {
    target.collapsed = false;
    target.openStamp = ++stampCounter;
    layout();
    while (contentBottom > bottom) {
      Section oldest = null;
      for (Section s : sections) {
        if (s != target && !s.collapsed && (oldest == null || s.openStamp < oldest.openStamp)) oldest = s;
      }
      if (oldest == null) break;
      oldest.collapsed = true;
      layout();
    }
  }

  void draw() {
    for (Section s : sections) {
      noStroke();
      fill(0xFF1C1E25);
      rect(x + 4, s.headerY, w - 8, s.HEADER_H, 3);
      fill(UI_YELLOW);
      float cx = x + 14;
      float cy = s.headerY + s.HEADER_H / 2;
      if (s.collapsed) triangle(cx - 3, cy - 4, cx - 3, cy + 4, cx + 3, cy);
      else triangle(cx - 4, cy - 2, cx + 4, cy - 2, cx, cy + 4);
      textSize(10);
      textAlign(LEFT, CENTER);
      text(s.title, x + 24, cy - 1);

      if (!s.collapsed) for (Widget k : s.kids) k.draw();
    }
    if (activeDropdown != null) activeDropdown.drawOverlay();
  }

  boolean press(float mx, float my) {
    if (activeDropdown != null) {
      activeDropdown.pressOverlay(mx, my);
      return true;
    }
    if (mx < x || mx > x + w) return false;

    for (Section s : sections) {
      if (my >= s.headerY && my <= s.headerY + s.HEADER_H) {
        if (s.collapsed) expand(s);
        else { s.collapsed = true; layout(); }
        return true;
      }
      if (s.collapsed) continue;
      for (Widget k : s.kids) {
        if (k.hit(mx, my) && k.press(mx, my)) {
          active = k;
          return true;
        }
      }
    }
    return true; // swallow clicks on empty panel space
  }

  void drag(float mx, float my) { if (active != null) active.drag(mx, my); }

  void release() {
    if (active != null) active.release();
    active = null;
  }
}
