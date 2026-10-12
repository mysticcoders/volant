// Accessibility helper for the installed-acceptance phases, run with `osascript -l JavaScript`.
// Finds elements in one process's windows by name, description, title, value or role so the phase
// scripts do not depend on SwiftUI's container nesting, which changes between macOS releases.
//
// Usage: ax.js <process> <command> [window] [match] [argument]
//   windows                          window titles, one per line
//   dump     <window>                role | subrole | name | description | value, one per element
//   find     <window> <match>        the first matching element, as in dump
//   press    <window> <match>        AXPress on the first match
//   frame    <window> <match>        x y width height of the first match, in screen points
//   focus    <window> <match>        sets AXFocused on the first match
//   set      <window> <match> <text> sets AXValue on the first match
//   select   <window> <match>        selects the row containing the first match
//   menu     <window> <match> <item> opens a pop-up button and picks a menu item by name
//   menuitems <window> <match>       the names in a pop-up button's menu
//   count    <window> <match>        how many elements match
//   frames   <window> <match>        every match, as in dump, followed by @ x y width height
// <window> is a window title or "*" for any window. <match> is "text", "role=AXButton",
// "role=AXButton:text" or "prefix=text"; text matches name, description, title, value or
// accessibility identifier exactly.
// A "#n" suffix picks the nth match, for unlabeled buttons that share their row's name.

function run(argv) {
  const se = Application("System Events");
  const [procName, command, windowName, match, argument] = argv;
  const proc = se.processes.byName(procName);
  const windows = () => proc.windows().filter(w => windowName === "*" || safe(() => w.name()) === windowName);
  if (command === "windows") return proc.windows().map(w => safe(() => w.name())).join("\n");

  const describe = e => [safe(() => e.role()), safe(() => e.subrole()), safe(() => e.name()),
    safe(() => e.description()), String(safe(() => e.value()) ?? "")].join(" | ");
  const elements = () => {
    const all = [];
    for (const w of windows()) {
      all.push(w);
      for (const e of safe(() => w.entireContents()) || []) all.push(e);
    }
    return all;
  };
  if (command === "dump") return elements().map(describe).join("\n");

  const nth = /#(\d+)$/.exec(match || "");
  const matches = predicate(nth ? match.slice(0, nth.index) : match);
  const all = elements().filter(e => matches(e));
  const found = nth ? all.slice(Number(nth[1]) - 1) : all;
  if (command === "count") return String(found.length);
  if (command === "frames") return found.map(e => describe(e) + " @ " + [...safe(() => e.position()) || [], ...safe(() => e.size()) || []].join(" ")).join("\n");
  if (!found.length) throw new Error(`no element matches ${match} in ${procName} ${windowName}`);
  const element = found[0];
  switch (command) {
    case "find": return describe(element);
    case "press": element.actions.byName("AXPress").perform(); return "pressed";
    case "frame": {
      const [x, y] = element.position(), [w, h] = element.size();
      return [x, y, w, h].join(" ");
    }
    case "focus": element.focused = true; return "focused";
    case "set": element.focused = true; element.value = argument; return "set";
    case "select": {
      let row = element;
      while (row && safe(() => row.role()) !== "AXRow") row = safe(() => row.attributes.byName("AXParent").value());
      if (!row) throw new Error(`${match} is not inside a row`);
      row.selected = true;
      return "selected";
    }
    case "menuitems": {
      element.actions.byName("AXPress").perform();
      delay(0.6);
      const names = element.menus[0].menuItems().map(i => safe(() => i.name())).filter(Boolean);
      se.keyCode(53);
      return names.join("\n");
    }
    case "menu": {
      element.actions.byName("AXPress").perform();
      delay(0.6);
      const items = element.menus[0].menuItems().filter(i => safe(() => i.name()) === argument);
      if (!items.length) {
        se.keyCode(53);
        throw new Error(`no menu item ${argument}`);
      }
      items[0].click();
      return "picked";
    }
  }
  throw new Error(`unknown command ${command}`);

  function predicate(spec) {
    let role = null, text = spec, prefix = false;
    if (spec.startsWith("role=")) {
      const rest = spec.slice(5);
      const colon = rest.indexOf(":");
      role = colon < 0 ? rest : rest.slice(0, colon);
      text = colon < 0 ? null : rest.slice(colon + 1);
    } else if (spec.startsWith("prefix=")) {
      text = spec.slice(7);
      prefix = true;
    }
    return e => {
      if (role && safe(() => e.role()) !== role) return false;
      if (text === null) return true;
      const fields = [safe(() => e.name()), safe(() => e.description()), safe(() => e.title()), safe(() => e.value()),
        safe(() => e.attributes.byName("AXIdentifier").value())];
      return fields.some(f => typeof f === "string" && (prefix ? f.startsWith(text) : f === text));
    };
  }
}

function safe(fn) {
  try { return fn(); } catch (error) { return null; }
}
