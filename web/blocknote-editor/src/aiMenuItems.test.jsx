import { describe, expect, it, vi } from "vitest";
import { AIExtension, getDefaultAIMenuItems } from "@blocknote/xl-ai";
import { getPromptProducerAIMenuItems } from "./aiMenuItems.jsx";

vi.mock("@blocknote/xl-ai", () => ({
  AIExtension: Symbol("AIExtension"),
  getDefaultAIMenuItems: vi.fn(() => [{ key: "accept", title: "Accept" }])
}));

function makeEditor({ selection } = {}) {
  const ai = { invokeAI: vi.fn() };
  const editor = {
    getExtension: vi.fn((extension) => (extension === AIExtension ? ai : undefined)),
    getSelection: vi.fn(() => selection)
  };

  return { ai, editor };
}

describe("Prompt Producer AI menu items", () => {
  it("shows the Prompt Producer AI actions in the requested order", () => {
    const { editor } = makeEditor();

    const items = getPromptProducerAIMenuItems(editor, "user-input", {});

    expect(items.map((item) => item.title)).toEqual([
      "Write a prompt about",
      "Elaborate",
      "Make more concise",
      "Add Action Items",
      "Tailor to this specific AI model:"
    ]);
  });

  it("uses prompt input for template actions", () => {
    const { editor } = makeEditor();
    const setPrompt = vi.fn();

    const items = getPromptProducerAIMenuItems(editor, "user-input", {
      model: "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
    });

    items.find((item) => item.key === "write_prompt_about").onItemClick(setPrompt);
    items.find((item) => item.key === "tailor_to_specific_ai_model").onItemClick(setPrompt);

    expect(setPrompt).toHaveBeenNthCalledWith(1, "Write a prompt about ");
    expect(setPrompt).toHaveBeenNthCalledWith(
      2,
      "Tailor this prompt to work best with @cf/meta/llama-3.3-70b-instruct-fp8-fast: "
    );
  });

  it("invokes BlockNote AI with selection state for editing actions", async () => {
    const { ai, editor } = makeEditor({ selection: { blocks: [] } });
    const items = getPromptProducerAIMenuItems(editor, "user-input", {});

    await items.find((item) => item.key === "elaborate").onItemClick();
    await items.find((item) => item.key === "make_more_concise").onItemClick();
    await items.find((item) => item.key === "add_action_items").onItemClick();

    expect(ai.invokeAI).toHaveBeenCalledTimes(3);
    expect(ai.invokeAI).toHaveBeenNthCalledWith(1, {
      userPrompt:
        "Elaborate this prompt with useful context, constraints, examples, and success criteria.",
      useSelection: true
    });
    expect(ai.invokeAI).toHaveBeenNthCalledWith(2, {
      userPrompt:
        "Make this prompt more concise while preserving the intent, constraints, and output requirements.",
      useSelection: true
    });
    expect(ai.invokeAI).toHaveBeenNthCalledWith(3, {
      userPrompt: "Add clear action items to this prompt.",
      useSelection: true
    });
  });

  it("keeps BlockNote review and error menu behavior", () => {
    const { editor } = makeEditor();

    expect(getPromptProducerAIMenuItems(editor, "user-reviewing", {})).toEqual([
      { key: "accept", title: "Accept" }
    ]);
    expect(getDefaultAIMenuItems).toHaveBeenCalledWith(editor, "user-reviewing");
  });
});
