import {
  CString,
  dlopen,
  FFIType,
  JSCallback,
  ptr,
  type Pointer,
} from "bun:ffi";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

export type MativeColor =
  | "primary"
  | "secondary"
  | "blue"
  | "red"
  | "green"
  | "orange"
  | "yellow"
  | "mint"
  | "indigo";

export type MativeWeight =
  | "light"
  | "regular"
  | "medium"
  | "semibold"
  | "bold"
  | "heavy";

export type MativeAlignment =
  | "topLeading"
  | "top"
  | "topTrailing"
  | "leading"
  | "center"
  | "trailing"
  | "bottomLeading"
  | "bottom"
  | "bottomTrailing";

export type MativeStackAlignment =
  | "leading"
  | "center"
  | "trailing"
  | "top"
  | "bottom";

export type MativeScrollAxis = "vertical" | "horizontal" | "both";

export type MativeButtonStyle =
  | "prominent"
  | "bordered"
  | "borderless"
  | "plain"
  | "link";

export type MativePadding =
  | number
  | {
      top?: number;
      bottom?: number;
      leading?: number;
      trailing?: number;
      horizontal?: number;
      vertical?: number;
    };

export type MativeFrame = {
  minWidth?: number;
  minHeight?: number;
  width?: number;
  height?: number;
  maxWidth?: number;
  maxHeight?: number;
  fillWidth?: boolean;
  fillHeight?: boolean;
  alignment?: MativeAlignment;
};

export type MativeStyle = {
  key?: string;
  padding?: MativePadding;
  frame?: MativeFrame;
  background?: MativeColor;
  selectable?: boolean;
  layoutPriority?: number;
  fixedWidth?: boolean;
  fixedHeight?: boolean;
};

type MativeNodeBase = MativeStyle & {
  type:
    | "vstack"
    | "hstack"
    | "zstack"
    | "scrollView"
    | "text"
    | "button"
    | "textField"
    | "spacer"
    | "divider";
  id?: string;
};

type InternalStackNode = MativeNodeBase & {
  type: "vstack" | "hstack";
  spacing?: number;
  alignment?: MativeStackAlignment;
  children: MativeNode[];
};

type InternalZStackNode = MativeNodeBase & {
  type: "zstack";
  alignment?: MativeAlignment;
  children: MativeNode[];
};

type InternalScrollViewNode = MativeNodeBase & {
  type: "scrollView";
  axis?: MativeScrollAxis;
  spacing?: number;
  alignment?: MativeStackAlignment;
  children: MativeNode[];
};

type InternalTextNode = MativeNodeBase & {
  type: "text";
  content: string;
  size?: number;
  color?: MativeColor;
  weight?: MativeWeight;
};

type InternalButtonNode = MativeNodeBase & {
  type: "button";
  id: string;
  label: string;
  buttonStyle?: MativeButtonStyle;
};

type InternalTextFieldNode = MativeNodeBase & {
  type: "textField";
  id: string;
  value: string;
  placeholder?: string;
};

type InternalSpacerNode = MativeNodeBase & {
  type: "spacer";
  minLength?: number;
};

type InternalDividerNode = MativeNodeBase & {
  type: "divider";
};

export type MativeNode =
  | InternalStackNode
  | InternalZStackNode
  | InternalScrollViewNode
  | InternalTextNode
  | InternalButtonNode
  | InternalTextFieldNode
  | InternalSpacerNode
  | InternalDividerNode;

export type MativeEventType = "action" | "change" | "submit" | "menu";

export type MativeEvent = {
  type: MativeEventType;
  id: string;
  value?: string;
  source?: "button" | "textField" | "menuItem";
  label?: string;
};

export type MativeMenuItem =
  | {
      type: "item";
      id: string;
      title: string;
      keyEquivalent?: string;
      enabled?: boolean;
    }
  | {
      type: "separator";
    }
  | {
      type: "submenu";
      title: string;
      enabled?: boolean;
      children: MativeMenuItem[];
    };

export type MativeMenuSection = {
  title: string;
  items: MativeMenuItem[];
};

const dylibCandidates = [
  join(import.meta.dir, "libmative.dylib"),
  join(process.cwd(), "libmative.dylib"),
  join(dirname(process.execPath), "libmative.dylib"),
];

const dylibPath =
  dylibCandidates.find((candidate) => existsSync(candidate)) ?? "./libmative.dylib";

const lib = dlopen(dylibPath, {
  mative_init: {
    args: [FFIType.ptr],
    returns: FFIType.void,
  },
  mative_poll: {
    args: [],
    returns: FFIType.void,
  },
  mative_update: {
    args: [FFIType.ptr],
    returns: FFIType.void,
  },
  mative_should_quit: {
    args: [],
    returns: FFIType.i32,
  },
  mative_set_menu: {
    args: [FFIType.ptr],
    returns: FFIType.void,
  },
});

function toCStringPointer(value: string) {
  const buffer = Buffer.from(`${value}\0`);
  return ptr(buffer);
}

class NativeBridge {
  init(callbackPointer: Pointer) {
    lib.symbols.mative_init(callbackPointer);
  }

  poll() {
    lib.symbols.mative_poll();
  }

  updateTree(payload: string) {
    lib.symbols.mative_update(toCStringPointer(payload));
  }

  updateMenu(payload: string) {
    lib.symbols.mative_set_menu(toCStringPointer(payload));
  }

  shouldQuit() {
    return lib.symbols.mative_should_quit() === 1;
  }
}

function parseNativeEvent(raw: string): MativeEvent {
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const type = parsed.type;
    const id = parsed.id;

    if (
      (type === "action" ||
        type === "change" ||
        type === "submit" ||
        type === "menu") &&
      typeof id === "string"
    ) {
      const eventType = type;
      const source =
        parsed.source === "button" ||
        parsed.source === "textField" ||
        parsed.source === "menuItem"
          ? parsed.source
          : undefined;
      const value = typeof parsed.value === "string" ? parsed.value : undefined;
      const label = typeof parsed.label === "string" ? parsed.label : undefined;

      return {
        type: eventType,
        id,
        value,
        source,
        label,
      };
    }
  } catch {
    // Fall back to the legacy plain-string payload.
  }

  return {
    type: "action",
    id: raw,
  };
}

class MativeRuntime {
  private bridge = new NativeBridge();
  private callback: JSCallback | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private cleanupInstalled = false;
  private state: "idle" | "running" | "stopped" = "idle";
  private lastTreePayload: string | null = null;
  private lastMenuPayload: string | null = null;
  private queuedTreePayload: string | null = null;
  private queuedMenuPayload: string | null = null;

  private installCleanupHooks() {
    if (this.cleanupInstalled) return;

    process.on("beforeExit", () => this.stop());
    process.on("SIGINT", () => {
      this.stop();
      process.exit(0);
    });
    process.on("SIGTERM", () => {
      this.stop();
      process.exit(0);
    });

    this.cleanupInstalled = true;
  }

  private flushQueuedState() {
    if (this.queuedMenuPayload) {
      this.bridge.updateMenu(this.queuedMenuPayload);
      this.lastMenuPayload = this.queuedMenuPayload;
      this.queuedMenuPayload = null;
    }

    if (this.queuedTreePayload) {
      this.bridge.updateTree(this.queuedTreePayload);
      this.lastTreePayload = this.queuedTreePayload;
      this.queuedTreePayload = null;
    }
  }

  private startPolling() {
    this.pollTimer = setInterval(() => {
      this.bridge.poll();

      if (this.bridge.shouldQuit()) {
        this.stop();
        process.exit(0);
      }
    }, 8);
  }

  start(onEvent: (event: MativeEvent) => void) {
    if (this.state === "running") return;

    this.installCleanupHooks();

    this.callback = new JSCallback(
      (eventPtr: number) => {
        const payload = new CString(eventPtr as unknown as Pointer).toString();
        onEvent(parseNativeEvent(payload));
      },
      {
        args: [FFIType.ptr],
        returns: FFIType.void,
      }
    );

    this.bridge.init(this.callback.ptr as unknown as Pointer);
    this.state = "running";
    this.flushQueuedState();
    this.startPolling();
  }

  render(tree: MativeNode) {
    const payload = JSON.stringify(tree);

    if (payload === this.lastTreePayload || payload === this.queuedTreePayload) {
      return;
    }

    if (this.state === "running") {
      this.bridge.updateTree(payload);
      this.lastTreePayload = payload;
      return;
    }

    this.queuedTreePayload = payload;
  }

  setMenu(menuSections: MativeMenuSection[]) {
    const payload = JSON.stringify(menuSections);

    if (payload === this.lastMenuPayload || payload === this.queuedMenuPayload) {
      return;
    }

    if (this.state === "running") {
      this.bridge.updateMenu(payload);
      this.lastMenuPayload = payload;
      return;
    }

    this.queuedMenuPayload = payload;
  }

  stop() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }

    if (this.callback) {
      this.callback.close();
      this.callback = null;
    }

    this.state = "stopped";
  }
}

const runtime = new MativeRuntime();

export const Mative = {
  start: (onEvent: (event: MativeEvent) => void) => runtime.start(onEvent),
  render: (tree: MativeNode) => runtime.render(tree),
  setMenu: (menuSections: MativeMenuSection[]) => runtime.setMenu(menuSections),
  stop: () => runtime.stop(),

  vstack(
    children: MativeNode[],
    options: Omit<InternalStackNode, "type" | "children"> = {}
  ): InternalStackNode {
    return {
      type: "vstack",
      children,
      ...options,
    };
  },

  hstack(
    children: MativeNode[],
    options: Omit<InternalStackNode, "type" | "children"> = {}
  ): InternalStackNode {
    return {
      type: "hstack",
      children,
      ...options,
    };
  },

  zstack(
    children: MativeNode[],
    options: Omit<InternalZStackNode, "type" | "children"> = {}
  ): InternalZStackNode {
    return {
      type: "zstack",
      children,
      ...options,
    };
  },

  scrollView(
    children: MativeNode[],
    options: Omit<InternalScrollViewNode, "type" | "children"> = {}
  ): InternalScrollViewNode {
    return {
      type: "scrollView",
      axis: "vertical",
      children,
      ...options,
    };
  },

  text(
    content: string,
    options: Omit<InternalTextNode, "type" | "content"> = {}
  ): InternalTextNode {
    return {
      type: "text",
      content,
      selectable: true,
      ...options,
    };
  },

  button(
    label: string,
    id: string,
    options: Omit<InternalButtonNode, "type" | "id" | "label"> = {}
  ): InternalButtonNode {
    return {
      type: "button",
      label,
      id,
      ...options,
    };
  },

  textField(
    id: string,
    value: string,
    options: Omit<InternalTextFieldNode, "type" | "id" | "value"> = {}
  ): InternalTextFieldNode {
    return {
      type: "textField",
      id,
      value,
      ...options,
    };
  },

  spacer(options: Omit<InternalSpacerNode, "type"> = {}): InternalSpacerNode {
    return {
      type: "spacer",
      ...options,
    };
  },

  divider(options: Omit<InternalDividerNode, "type"> = {}): InternalDividerNode {
    return {
      type: "divider",
      ...options,
    };
  },

  menuSection(title: string, items: MativeMenuItem[]): MativeMenuSection {
    return { title, items };
  },

  menuItem(
    title: string,
    id: string,
    options: { keyEquivalent?: string; enabled?: boolean } = {}
  ): MativeMenuItem {
    return {
      type: "item",
      title,
      id,
      ...options,
    };
  },

  menuSeparator(): MativeMenuItem {
    return { type: "separator" };
  },

  submenu(
    title: string,
    children: MativeMenuItem[],
    options: { enabled?: boolean } = {}
  ): MativeMenuItem {
    return {
      type: "submenu",
      title,
      children,
      ...options,
    };
  },
};