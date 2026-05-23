import "@blocknote/core/fonts/inter.css";
import "@blocknote/mantine/style.css";
import { BlockNoteView } from "@blocknote/mantine";
import {
  AIExtension,
  AIMenu,
  AIMenuController,
  AIToolbarButton,
  getAISlashMenuItems
} from "@blocknote/xl-ai";
import "@blocknote/xl-ai/style.css";
import { en } from "@blocknote/core/locales";
import { en as aiEn } from "@blocknote/xl-ai/locales";
import {
  SuggestionMenuController,
  getDefaultReactSlashMenuItems,
  useCreateBlockNote,
  FormattingToolbar,
  FormattingToolbarController
} from "@blocknote/react";
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { getPromptProducerAIMenuItems } from "./aiMenuItems.jsx";
import "./styles.css";

const nord = {
  polarNight0: "#2E3440",
  polarNight1: "#3B4252",
  polarNight2: "#434C5E",
  polarNight3: "#4C566A",
  snow0: "#D8DEE9",
  snow1: "#E5E9F0",
  snow2: "#ECEFF4",
  frost0: "#8FBCBB",
  frost1: "#88C0D0",
  frost2: "#81A1C1",
  frost3: "#5E81AC",
  red: "#BF616A",
  orange: "#D08770",
  yellow: "#EBCB8B",
  green: "#A3BE8C",
  purple: "#B48EAD"
};

const nordFont =
  '"Inter", ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

const nordDarkTheme = {
  colors: {
    editor: { text: nord.snow2, background: nord.polarNight0 },
    menu: { text: nord.snow2, background: nord.polarNight1 },
    tooltip: { text: nord.snow2, background: nord.polarNight2 },
    hovered: { text: nord.snow2, background: nord.polarNight2 },
    selected: { text: nord.polarNight0, background: nord.frost1 },
    disabled: { text: nord.polarNight3, background: nord.polarNight1 },
    shadow: "rgba(15, 17, 22, 0.42)",
    border: nord.polarNight3,
    sideMenu: nord.frost2,
    highlights: {
      gray: { text: nord.snow2, background: nord.polarNight3 },
      brown: { text: nord.snow2, background: nord.orange },
      red: { text: nord.snow2, background: nord.red },
      orange: { text: nord.polarNight0, background: nord.orange },
      yellow: { text: nord.polarNight0, background: nord.yellow },
      green: { text: nord.polarNight0, background: nord.green },
      blue: { text: nord.polarNight0, background: nord.frost1 },
      purple: { text: nord.snow2, background: nord.purple },
      pink: { text: nord.snow2, background: nord.purple }
    }
  },
  borderRadius: 6,
  fontFamily: nordFont
};

const nordLightTheme = {
  colors: {
    editor: { text: nord.polarNight0, background: nord.snow2 },
    menu: { text: nord.polarNight0, background: nord.snow1 },
    tooltip: { text: nord.snow2, background: nord.polarNight2 },
    hovered: { text: nord.polarNight0, background: nord.snow0 },
    selected: { text: nord.polarNight0, background: nord.frost1 },
    disabled: { text: nord.polarNight3, background: nord.snow0 },
    shadow: "rgba(46, 52, 64, 0.24)",
    border: nord.snow0,
    sideMenu: nord.frost3,
    highlights: {
      gray: { text: nord.polarNight0, background: nord.snow0 },
      brown: { text: nord.polarNight0, background: "#E2C5B5" },
      red: { text: nord.polarNight0, background: "#E7B3B8" },
      orange: { text: nord.polarNight0, background: "#EAC5B6" },
      yellow: { text: nord.polarNight0, background: "#F2DDA9" },
      green: { text: nord.polarNight0, background: "#C9DDBE" },
      blue: { text: nord.polarNight0, background: "#C5D6EA" },
      purple: { text: nord.polarNight0, background: "#DAC5D6" },
      pink: { text: nord.polarNight0, background: "#DAC5D6" }
    }
  },
  borderRadius: 6,
  fontFamily: nordFont
};

function postMessage(message) {
  window.webkit?.messageHandlers?.blockNoteBridge?.postMessage(message);
}

function debugSnippet(value, limit = 160) {
  return String(value ?? "")
    .replaceAll("\n", " ")
    .replaceAll("\r", " ")
    .trim()
    .slice(0, limit);
}

function logAIDebug(phase, details = {}) {
  const detail = Object.entries(details)
    .map(([key, value]) => `${key}=${typeof value === "string" ? value : JSON.stringify(value)}`)
    .join(" ");

  postMessage({
    type: "aiDebug",
    phase,
    detail: debugSnippet(detail, 800)
  });
}

function getInitialAIConfig() {
  return normalizeAIConfig(
    (typeof window !== "undefined" && window.__INITIAL_AI_CONFIG) || {}
  );
}

function normalizeAIConfig(config = {}) {
  return {
    model: typeof config.model === "string" ? config.model : "",
    nativeAIAvailable: Boolean(config.nativeAIAvailable),
    nativeAIProviderName:
      typeof config.nativeAIProviderName === "string" ? config.nativeAIProviderName : ""
  };
}

function emptyParagraph() {
  return [{ type: "paragraph", content: "" }];
}

function initialTheme() {
  return window.matchMedia?.("(prefers-color-scheme: light)")?.matches ? "light" : "dark";
}

const pendingNativeAIRequests = new Map();

window.promptProducerResolveAI = function resolveNativeAIRequest(message) {
  const requestID = typeof message?.requestID === "string" ? message.requestID : "";
  const pendingRequest = pendingNativeAIRequests.get(requestID);
  if (!pendingRequest) {
    logAIDebug("native-resolve-missing", { requestID });
    return;
  }

  pendingNativeAIRequests.delete(requestID);

  if (typeof message.error === "string" && message.error.length > 0) {
    logAIDebug("native-resolve-error", {
      requestID,
      source: pendingRequest.source,
      error: message.error
    });
    pendingRequest.reject(new Error(message.error));
    return;
  }

  const text = typeof message.text === "string" ? message.text : "";
  logAIDebug("native-resolve-success", {
    requestID,
    source: pendingRequest.source,
    outputLen: text.length
  });
  pendingRequest.resolve(text);
};

function textFromMessages(messages) {
  const userMessages = messages.filter((message) => message.role === "user");
  const message = userMessages.at(-1) ?? messages.at(-1);
  return (message?.parts ?? [])
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text)
    .join("\n")
    .trim();
}

function uiMessageStreamFromText(text) {
  return new ReadableStream({
    start(controller) {
      controller.enqueue({ type: "start" });
      controller.enqueue({ type: "start-step" });
      controller.enqueue({ type: "text-start", id: "text-1" });
      controller.enqueue({ type: "text-delta", id: "text-1", delta: text });
      controller.enqueue({ type: "text-end", id: "text-1" });
      controller.enqueue({ type: "finish-step" });
      controller.enqueue({ type: "finish", finishReason: "stop" });
      controller.close();
    }
  });
}

function requestNativeAI({ prompt, context, abortSignal, source = "unknown" }) {
  const requestID = crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  const normalizedPrompt = typeof prompt === "string" ? prompt : "";
  const normalizedContext = typeof context === "string" ? context : "";

  return new Promise((resolve, reject) => {
    if (abortSignal?.aborted) {
      reject(new DOMException("AI request was aborted.", "AbortError"));
      return;
    }

    logAIDebug("native-request", {
      requestID,
      source,
      promptLen: normalizedPrompt.length,
      contextLen: normalizedContext.length
    });

    pendingNativeAIRequests.set(requestID, { resolve, reject, source });
    abortSignal?.addEventListener(
      "abort",
      () => {
        pendingNativeAIRequests.delete(requestID);
        logAIDebug("native-request-abort", { requestID, source });
        reject(new DOMException("AI request was aborted.", "AbortError"));
      },
      { once: true }
    );

    postMessage({
      type: "aiRequest",
      requestID,
      prompt: normalizedPrompt,
      context: normalizedContext
    });
  });
}

function describeMessages(messages = []) {
  return messages.map((message) => ({
    role: message.role,
    partTypes: (message.parts ?? []).map((part) => part.type),
    metadataKeys: Object.keys(message.metadata ?? {})
  }));
}

function describeToolDefinitions(toolDefinitions) {
  if (Array.isArray(toolDefinitions)) {
    return toolDefinitions.map((definition) => definition?.name ?? definition?.toolName ?? "unknown");
  }

  if (toolDefinitions && typeof toolDefinitions === "object") {
    return Object.keys(toolDefinitions);
  }

  return [];
}

function createNativeAITransport(getContext) {
  return {
    async sendMessages({ messages, body, abortSignal }) {
      const prompt = textFromMessages(messages);
      const context = getContext();
      logAIDebug("transport-sendMessages", {
        promptLen: prompt.length,
        contextLen: context.length,
        bodyKeys: Object.keys(body ?? {}),
        toolDefinitions: describeToolDefinitions(body?.toolDefinitions),
        messages: describeMessages(messages)
      });
      const text = await requestNativeAI({
        prompt,
        context,
        abortSignal,
        source: "blocknote-transport"
      });
      return uiMessageStreamFromText(text);
    },
    async reconnectToStream() {
      return null;
    }
  };
}

function App() {
  const [theme, setTheme] = useState(() => initialTheme());
  const [isReadyForPaint, setIsReadyForPaint] = useState(false);
  const [aiConfig, setAIConfig] = useState(() => getInitialAIConfig());
  const aiConfigRef = useRef(aiConfig);
  const markdownRef = useRef("");

  useEffect(() => {
    aiConfigRef.current = aiConfig;
  }, [aiConfig]);

  const aiTransport = useMemo(() => {
    return createNativeAITransport(() => markdownRef.current);
  }, []);

  const editor = useCreateBlockNote({
    dictionary: { ...en, ai: aiEn },
    initialContent: emptyParagraph(),
    extensions: [AIExtension({ transport: aiTransport })]
  });

  const emitMarkdown = useCallback(async () => {
    const markdown = await editor.blocksToMarkdownLossy(editor.document);
    markdownRef.current = markdown;
    postMessage({ type: "change", markdown });
  }, [editor]);

  const setMarkdown = useCallback(
    async (markdown) => {
      const normalizedMarkdown = typeof markdown === "string" ? markdown : "";
      markdownRef.current = normalizedMarkdown;
      const blocks = normalizedMarkdown.trim()
        ? await editor.tryParseMarkdownToBlocks(normalizedMarkdown)
        : emptyParagraph();
      editor.replaceBlocks(editor.document, blocks);
      setIsReadyForPaint(true);
    },
    [editor]
  );

  const runNativeAIEdit = useCallback(
    async (userPrompt) => {
      const prompt = typeof userPrompt === "string" ? userPrompt.trim() : "";
      if (!prompt) {
        return;
      }

      const context = await editor.blocksToMarkdownLossy(editor.document);
      markdownRef.current = context;
      logAIDebug("native-edit-start", {
        promptLen: prompt.length,
        contextLen: context.length
      });

      try {
        const generatedMarkdown = (await requestNativeAI({
          prompt,
          context,
          source: "manual-native-edit"
        }))?.trim();
        if (!generatedMarkdown) {
          throw new Error("Local Apple Foundation Models returned an empty response.");
        }
        logAIDebug("native-edit-apply", {
          generatedLen: generatedMarkdown.length
        });

        const blocks = generatedMarkdown
          ? await editor.tryParseMarkdownToBlocks(generatedMarkdown)
          : emptyParagraph();
        editor.replaceBlocks(editor.document, blocks.length > 0 ? blocks : emptyParagraph());

        const nextMarkdown = await editor.blocksToMarkdownLossy(editor.document);
        markdownRef.current = nextMarkdown;
        postMessage({ type: "change", markdown: nextMarkdown });
        editor.getExtension(AIExtension)?.closeAIMenu?.();
        editor.focus();
      } catch (error) {
        postMessage({
          type: "error",
          message: error instanceof Error ? error.message : "Local AI request failed."
        });
        throw error;
      }
    },
    [editor]
  );

  const openAIMenuAtCursor = useCallback(() => {
    const aiExtension = editor.getExtension(AIExtension);
    const cursor = editor.getTextCursorPosition();
    const targetBlock = cursor.block.content?.length === 0 && cursor.prevBlock
      ? cursor.prevBlock
      : cursor.block;

    if (targetBlock) {
      aiExtension?.openAIMenuAtBlock(targetBlock.id);
    }
  }, [editor]);

  useEffect(() => {
    editor.isEditable = true;

    window.promptProducer = {
      setMarkdown,
      setAIConfig(nextConfig) {
        setAIConfig(normalizeAIConfig(nextConfig));
      },
      setTheme(nextTheme) {
        setTheme(nextTheme === "dark" ? "dark" : "light");
      },
      focus() {
        editor.isEditable = true;
        editor.focus();
      },
      openAI() {
        openAIMenuAtCursor();
      }
    };

    postMessage({ type: "ready" });

    return () => {
      delete window.promptProducer;
    };
  }, [editor, openAIMenuAtCursor, setMarkdown]);

  const focusEditor = useCallback(
    (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (!target || target.closest("[contenteditable='true']") || target.closest(".bn-block-content")) {
        return;
      }

      editor.isEditable = true;
      const lastBlock = editor.document.at(-1);
      if (lastBlock) {
        editor.setTextCursorPosition(lastBlock, "end");
      }
      editor.focus();
    },
    [editor]
  );

  const getSlashMenuItems = useCallback(
    async (query) => {
      const defaultItems = await getDefaultReactSlashMenuItems(editor);
      const lowerQuery = query.toLowerCase();
      const filteredDefaultItems = defaultItems.filter((item) =>
        item.title.toLowerCase().includes(lowerQuery)
      );

      const aiItems = await getAISlashMenuItems(editor);
      return [...aiItems, ...filteredDefaultItems];
    },
    [editor]
  );

  const getAIMenuItems = useCallback(
    (menuEditor, aiResponseStatus) =>
      getPromptProducerAIMenuItems(
        menuEditor,
        aiResponseStatus,
        aiConfigRef.current,
        runNativeAIEdit
      ),
    [runNativeAIEdit]
  );

  const PromptProducerAIMenu = useCallback(
    (props) => (
      <AIMenu
        {...props}
        items={getAIMenuItems}
        onManualPromptSubmit={runNativeAIEdit}
      />
    ),
    [getAIMenuItems, runNativeAIEdit]
  );

  return (
    <div className={`editor-shell ${isReadyForPaint ? "is-ready" : ""}`} data-theme={theme}>
      <div className="editor-frame" onPointerDown={focusEditor}>
        <BlockNoteView
          editor={editor}
          editable={true}
          onChange={emitMarkdown}
          formattingToolbar={false}
          theme={theme === "dark" ? nordDarkTheme : nordLightTheme}
          className="prompt-editor"
          slashMenu={false}
        >
          <button
            className="editor-ai-trigger"
            type="button"
            title="Ask AI"
            aria-label="Ask AI"
            onPointerDown={(event) => event.preventDefault()}
            onClick={openAIMenuAtCursor}
          >
            AI
          </button>
          <AIMenuController aiMenu={PromptProducerAIMenu} />
          <FormattingToolbarController
            formattingToolbar={() => (
              <FormattingToolbar>
                <AIToolbarButton key="aiButton" />
              </FormattingToolbar>
            )}
          />
          <SuggestionMenuController
            triggerCharacter="/"
            getItems={getSlashMenuItems}
            shouldOpen={(state) => !state.selection.$from.parent.type.isInGroup("tableContent")}
          />
        </BlockNoteView>
      </div>
    </div>
  );
}

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
