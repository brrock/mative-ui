import { Mative, type MativeEvent } from "./native";

let count = 0;
let history: string[] = [];
let draft = "Selectable text now works on macOS.";

function addHistory(entry: string) {
  history.push(entry);
  history = history.slice(-6);
}

function installMenu() {
  Mative.setMenu([
    Mative.menuSection("Counter", [
      Mative.menuItem("Increment", "inc", { keyEquivalent: "+" }),
      Mative.menuItem("Decrement", "dec", { keyEquivalent: "-" }),
      Mative.menuSeparator(),
      Mative.menuItem("Reset", "reset", { keyEquivalent: "r" }),
    ]),
    Mative.menuSection("History", [
      Mative.menuItem("Clear History", "clear-history"),
    ]),
  ]);
}

function view() {
  return Mative.scrollView(
    [
      Mative.vstack(
        [
          Mative.zstack(
            [
              Mative.text("mativeUi", {
                key: "title-shadow",
                size: 32,
                color: "mint",
                weight: "heavy",
                padding: { top: 3, leading: 3 },
                fixedWidth: false,
              }),
              Mative.text("mativeUi", {
                key: "title",
                size: 32,
                color: "indigo",
                weight: "heavy",
              }),
            ],
            {
              key: "title-stack",
              alignment: "topLeading",
              frame: { fillWidth: true, alignment: "leading" },
            }
          ),
          Mative.text("SwiftUI rendered by Bun FFI with menus, inputs, layout primitives, and richer events.", {
            key: "subtitle",
            size: 14,
            color: "secondary",
            frame: { fillWidth: true, alignment: "leading", maxWidth: 720 },
          }),
          Mative.text("You can highlight this text now.", {
            key: "selection-note",
            size: 13,
            color: "mint",
          }),
          Mative.divider({ key: "hero-divider" }),
          Mative.text(`Count: ${count}`, {
            key: "count",
            size: 26,
            weight: "semibold",
            padding: { bottom: 2 },
          }),
          Mative.hstack(
            [
              Mative.button("−1", "dec", {
                key: "dec-button",
                buttonStyle: "borderless",
              }),
              Mative.button("+1", "inc", {
                key: "inc-button",
                buttonStyle: "prominent",
              }),
              Mative.button("Reset", "reset", {
                key: "reset-button",
                buttonStyle: "bordered",
              }),
              Mative.button("Docs", "docs", {
                key: "docs-button",
                buttonStyle: "link",
              }),
            ],
            {
              key: "actions",
              spacing: 10,
              alignment: "center",
            }
          ),
          Mative.divider({ key: "content-divider", padding: { vertical: 6 } }),
          Mative.text("Draft note", {
            key: "draft-label",
            size: 14,
            color: "secondary",
            weight: "medium",
          }),
          Mative.textField("draft", draft, {
            key: "draft-input",
            placeholder: "Type here and press return",
            frame: { fillWidth: true, minWidth: 320, maxWidth: 720, alignment: "leading" },
          }),
          Mative.text("Recent events", {
            key: "history-label",
            size: 14,
            color: "secondary",
            weight: "medium",
          }),
          ...history.map((entry) =>
            Mative.text(`• ${entry}`, {
              key: `history-${entry}`,
              size: 13,
              color: "secondary",
              frame: { fillWidth: true, alignment: "leading", maxWidth: 720 },
            })
          ),
          Mative.spacer({
            key: "tail-spacer",
            minLength: 20,
            layoutPriority: 1,
          }),
        ],
        {
          key: "content",
          spacing: 14,
          alignment: "leading",
          padding: 24,
          frame: {
            fillWidth: true,
            fillHeight: true,
            alignment: "topLeading",
          },
        }
      ),
    ],
    {
      key: "root-scroll",
      axis: "vertical",
      frame: {
        fillWidth: true,
        fillHeight: true,
        alignment: "topLeading",
      },
    }
  );
}

function render() {
  const tree = view();
  Mative.render(tree);
}

function handleEvent(event: MativeEvent) {
  if (event.type === "change" && event.id === "draft") {
    draft = event.value ?? "";
    render();
    return;
  }

  if (event.type === "submit" && event.id === "draft") {
    addHistory(`Submitted ${event.source}: ${event.value ?? ""}`);
    render();
    return;
  }

  if (event.id === "inc") {
    count += 1;
    addHistory(`${event.label ?? "Increment"} via ${event.source ?? event.type}`);
  } else if (event.id === "dec") {
    count -= 1;
    addHistory(`${event.label ?? "Decrement"} via ${event.source ?? event.type}`);
  } else if (event.id === "reset") {
    count = 0;
    history = [`${event.label ?? "Reset"} via ${event.source ?? event.type}`];
  } else if (event.id === "clear-history") {
    history = ["History cleared"];
  } else if (event.id === "docs") {
    addHistory("Docs link pressed");
  }

  render();
}

Mative.start(handleEvent);
installMenu();
render();